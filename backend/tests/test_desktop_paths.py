import os
from pathlib import Path
import subprocess
import sys


def test_packaged_backend_uses_client_private_paths(tmp_path):
    private=tmp_path/'client.env'
    private.write_text('DATABASE_USER=client_test\nDATABASE_PASSWORD=test-only-password\nDATABASE_HOST=127.0.0.1\nDATABASE_PORT=15432\nDATABASE_NAME=client_test\n')
    process_env=os.environ.copy()
    for key in list(process_env):
        if key.startswith('DATABASE_'):process_env.pop(key)
    process_env.update(ACADEMY_ENV_FILE=str(private),ACADEMY_DATA_DIR=str(tmp_path/'client-data'), PYTHONTZPATH="")
    code='''from pathlib import Path
import os
from app.db.database import DATABASE_URL, ENV_PATH
from app.quran import CACHE_DIR
from app.integrations import ENV_PATH as INTEGRATION_PATH
assert ENV_PATH == Path(os.environ['ACADEMY_ENV_FILE'])
assert INTEGRATION_PATH == ENV_PATH
assert DATABASE_URL.username == 'client_test'
assert DATABASE_URL.host == '127.0.0.1' and DATABASE_URL.port == 15432
assert CACHE_DIR == Path(os.environ['ACADEMY_DATA_DIR']) / 'quran'
from zoneinfo import ZoneInfo
assert ZoneInfo('Asia/Karachi').key == 'Asia/Karachi'
print('Client data paths verified')
'''
    root=Path(__file__).resolve().parents[1]
    result=subprocess.run([sys.executable,'-c',code],cwd=root,env=process_env,capture_output=True,text=True)
    assert result.returncode==0,result.stderr
    assert result.stdout.strip()=='Client data paths verified'
