"""Publish only isolated unit-test diagnostics, never actual client data."""
import io
import json
from pathlib import Path
import traceback
import unittest

root=Path(__file__).resolve().parents[2]
report={}
try:
    suite=unittest.defaultTestLoader.discover(str(Path(__file__).parent),pattern='test_*.py')
    stream=io.StringIO()
    result=unittest.TextTestRunner(stream=stream,verbosity=2).run(suite)
    report={'passed':result.wasSuccessful(),'tests':result.testsRun,
        'failures':[{'test':str(case),'trace':trace} for case,trace in result.failures+result.errors],
        'output':stream.getvalue()}
except Exception:
    report={'passed':False,'tests':0,'output':traceback.format_exc()}
path=root/'packaging/windows/ci-result.json'
path.write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps({'passed':report['passed'],'tests':report['tests']}))
raise SystemExit(0 if report['passed'] else 1)
