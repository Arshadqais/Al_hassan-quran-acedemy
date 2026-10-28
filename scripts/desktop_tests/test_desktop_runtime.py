import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'packaging' / 'windows'))
from desktop_runtime import DesktopRuntime, DesktopError


class ClientDataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app, self.data = self.root / 'program', self.root / 'client-data'
        self.app.mkdir()
        (self.app / 'build.json').write_text(json.dumps({'version':'0.1.0','commit':'new-build'}))
        self.runtime = DesktopRuntime(self.app, self.data)
        # ACL changes are integration-tested by the actual Windows install job.
        self.acl = patch('desktop_runtime.restrict_directory', side_effect=lambda p:p.mkdir(parents=True,exist_ok=True))
        self.acl.start(); self.addCleanup(self.acl.stop)
        self.runtime.initialize()

    def test_client_credentials_are_generated_once_and_preserved(self):
        first = self.runtime.env_file.read_text()
        self.assertNotIn('DATABASE_PASSWORD=\n',first)
        self.runtime.env_file.write_text(first+'LIVEKIT_URL=wss://client.example\n')
        self.runtime.initialize()
        self.assertEqual(self.runtime.env_file.read_text(), first+'LIVEKIT_URL=wss://client.example\n')
        self.assertFalse(list(self.app.rglob('*.env')))

    def test_developer_environment_cannot_redirect_client_database(self):
        with patch.dict(os.environ, {'DATABASE_URL':'postgresql://developer.invalid/dev','LIVEKIT_API_SECRET':'not-client-secret','WHATSAPP_ACCESS_TOKEN':'not-client-token'}):
            env=self.runtime.process_env()
        self.assertNotIn('DATABASE_URL',env)
        self.assertNotIn('LIVEKIT_API_SECRET',env)
        self.assertNotIn('WHATSAPP_ACCESS_TOKEN',env)
        self.assertEqual(env['ACADEMY_ENV_FILE'],str(self.data/'backend.env'))

    def test_data_cannot_live_inside_replaceable_program_directory(self):
        with self.assertRaises(DesktopError):DesktopRuntime(self.app,self.app/'data')

    def test_unknown_cluster_files_are_never_deleted_or_reinitialized(self):
        self.runtime.cluster.mkdir()
        saved=self.runtime.cluster/'valuable-data'; saved.write_text('preserve')
        with patch('desktop_runtime.run') as command:
            with self.assertRaises(DesktopError):self.runtime.start_postgres()
        command.assert_not_called()
        self.assertEqual(saved.read_text(),'preserve')

    def test_different_postgresql_major_is_preserved_and_rejected(self):
        self.runtime.cluster.mkdir(); (self.runtime.cluster/'PG_VERSION').write_text('16')
        with self.assertRaises(DesktopError):self.runtime.start_postgres()
        self.assertEqual((self.runtime.cluster/'PG_VERSION').read_text(),'16')

    def test_occupied_port_does_not_adopt_an_unrelated_database(self):
        self.runtime.cluster.mkdir();(self.runtime.cluster/'PG_VERSION').write_text('17')
        with patch('desktop_runtime.run',return_value=subprocess.CompletedProcess([],3)),patch('desktop_runtime.port_in_use',return_value=True):
            with self.assertRaises(DesktopError):self.runtime.start_postgres()
        self.assertFalse(self.runtime.pg_started)

    def test_failed_backup_blocks_upgrade_and_keeps_old_marker(self):
        marker=self.data/'installed-build.json'; marker.write_text(json.dumps({'commit':'old-build'}))
        with patch.object(self.runtime,'backup',side_effect=DesktopError('backup failed')),patch.object(self.runtime,'helper') as helper:
            with self.assertRaises(DesktopError):self.runtime.migrate()
        helper.assert_not_called()
        self.assertEqual(json.loads(marker.read_text())['commit'],'old-build')

    def test_backup_precedes_migration_and_failed_migration_keeps_old_marker(self):
        marker=self.data/'installed-build.json';marker.write_text(json.dumps({'commit':'old-build'}))
        events=[]
        with patch.object(self.runtime,'backup',side_effect=lambda:events.append('backup')),patch.object(self.runtime,'helper',side_effect=lambda action:events.append(action)):
            self.runtime.migrate()
        self.assertEqual(events,['backup','migrate'])
        self.assertEqual(json.loads(marker.read_text())['commit'],'new-build')
        marker.write_text(json.dumps({'commit':'old-build'}))
        with patch.object(self.runtime,'backup'),patch.object(self.runtime,'helper',side_effect=DesktopError('migration failed')):
            with self.assertRaises(DesktopError):self.runtime.migrate()
        self.assertEqual(json.loads(marker.read_text())['commit'],'old-build')

    def test_dump_password_never_appears_in_arguments(self):
        seen=[]
        def command(args,**kwargs):
            seen.extend(str(v) for v in args)
            self.assertEqual(kwargs['env']['PGPASSWORD'],self.runtime.config['DATABASE_PASSWORD'])
            Path(args[args.index('--file')+1]).write_bytes(b'nonempty-test-dump')
        with patch('desktop_runtime.run',side_effect=command):path=self.runtime.backup()
        self.assertTrue(path.exists())
        self.assertNotIn(self.runtime.config['DATABASE_PASSWORD'],' '.join(seen))
        self.assertFalse(list(self.runtime.backups.glob('*.partial')))


if __name__=='__main__':unittest.main()
