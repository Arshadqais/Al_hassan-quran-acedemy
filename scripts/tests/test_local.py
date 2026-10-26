import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "local.py"
spec = importlib.util.spec_from_file_location("academy_local", SCRIPT)
local = importlib.util.module_from_spec(spec)
spec.loader.exec_module(local)


class LocalWorkflowTests(unittest.TestCase):
    def test_env_creation_is_private_and_existing_file_is_not_replaced(self):
        with tempfile.TemporaryDirectory() as folder:
            env_file = Path(folder) / ".env"
            with patch.object(local, "ENV_FILE", env_file):
                local.initialize_env()
                text = env_file.read_text()
                self.assertIn("DATABASE_PASSWORD=", text)
                self.assertNotIn("DATABASE_PASSWORD=\n", text)
                self.assertEqual(env_file.stat().st_mode & 0o777, 0o600)
                env_file.write_text("DATABASE_PASSWORD=existing-local-test-password\n")
                local.initialize_env()
                self.assertEqual(
                    env_file.read_text(),
                    "DATABASE_PASSWORD=existing-local-test-password\n",
                )

    def test_flutter_repair_fetches_host_tester_and_web_with_force(self):
        with (
            patch.object(local, "flutter", return_value="flutter"),
            patch.object(local, "run") as run,
        ):
            local.repair_flutter(force=True)
        self.assertEqual(
            run.call_args_list[0].args[0],
            [
                "flutter",
                "--suppress-analytics",
                "precache",
                "--universal",
                "--web",
                "--force",
            ],
        )
        self.assertEqual(run.call_args_list[0].kwargs["cwd"], local.FRONTEND)
        self.assertEqual(run.call_args_list[1].kwargs["cwd"], local.FRONTEND)

    def test_stopped_docker_has_actionable_error_before_migration(self):
        config = {
            "DATABASE_PASSWORD": "fake-test-password",
            "DATABASE_HOST": "127.0.0.1",
        }
        with (
            patch.object(local, "settings", return_value=config),
            patch.object(local.shutil, "which", return_value="docker"),
            patch.object(local, "run", side_effect=local.LocalError("failed")),
        ):
            with self.assertRaisesRegex(local.LocalError, "Open Docker Desktop"):
                local.database()

    def test_database_uses_same_credentials_waits_and_migrates_from_backend(self):
        config = {
            "DATABASE_PASSWORD": "fake-test-password",
            "DATABASE_HOST": "localhost",
            "DATABASE_USER": "testuser",
            "DATABASE_NAME": "test_db",
            "DATABASE_PORT": "5544",
        }
        with (
            patch.object(local, "settings", return_value=config),
            patch.object(local.shutil, "which", return_value="docker"),
            patch.object(local, "run") as run,
            patch.object(
                local.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)
            ),
        ):
            local.database()
        compose = run.call_args_list[1]
        self.assertIn("--wait", compose.args[0])
        self.assertEqual(
            compose.kwargs["env"]["POSTGRES_PASSWORD"], "fake-test-password"
        )
        self.assertEqual(compose.kwargs["env"]["DATABASE_PORT"], "5544")
        self.assertEqual(run.call_args_list[-1].kwargs["cwd"], local.BACKEND)
        self.assertEqual(run.call_args_list[-1].args[0][-2:], ["upgrade", "head"])

    def test_commands_use_project_paths_even_from_backend_directory(self):
        result = subprocess.run(
            [local.sys.executable, str(SCRIPT), "--help"],
            cwd=local.BACKEND,
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn("repair-flutter", result.stdout)
        self.assertEqual(local.ROOT, SCRIPT.parents[1])

    def test_web_connects_to_requested_api_and_cors_matches_local_origin(self):
        from types import SimpleNamespace

        args = SimpleNamespace(api_port=18000, web_port=18090)
        with patch.object(local, "flutter", return_value="flutter"):
            self.assertIn(
                "--dart-define=API_BASE_URL=http://127.0.0.1:18000",
                local.web_command(args),
            )
        with patch.object(
            local,
            "settings",
            return_value={"ACADEMY_ORIGINS": "https://academy.example"},
        ):
            origins = local.server_env(18090)["ACADEMY_ORIGINS"]
        self.assertIn("https://academy.example", origins)
        self.assertIn("http://127.0.0.1:18090", origins)


if __name__ == "__main__":
    unittest.main()
