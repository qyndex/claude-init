#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-6/AC-8: execute actual workflow shell, preserving default-off dispatch."""
import json,os,subprocess,tempfile
from pathlib import Path
import yaml
workflow=yaml.safe_load(Path('.github/workflows/factory-hosted-digest.yml').read_text())
step=next(step for job in workflow['jobs'].values() for step in job['steps'] if step.get('name')=='Deliver with authoritative branch checkpoints')
with tempfile.TemporaryDirectory() as tmp:
 root=Path(tmp);stub=root/'python3';stub.write_text('#!/usr/bin/env python3\nimport json,os,sys\nfrom pathlib import Path\nPath(os.environ["CALLS"]).write_text(json.dumps(sys.argv[1:]))\n')
 # Use the actual interpreter in the stub shebang; avoid recursive PATH lookup.
 import sys
 stub.write_text(stub.read_text().replace('#!/usr/bin/env python3','#!'+sys.executable));stub.chmod(0o755)
 for flag in ('false','true','invalid'):
  calls=root/'calls';calls.unlink(missing_ok=True)
  env={'PATH':str(root)+os.pathsep+os.environ['PATH'],'RUNNER_TEMP':str(root),'CALLS':str(calls),'FACTORY_REPORTING_APP_WRITER_ENABLED':flag}
  result=subprocess.run(['bash','-e','-c',step['run']],env=env,capture_output=True,text=True)
  if flag=='invalid':assert result.returncode!=0 and not calls.exists()
  else:
   assert result.returncode==0,(flag,result.stderr)
   expected='.claude/scripts/factory-reporting-driver.py' if flag=='true' else '.claude/scripts/factory-git-state.py'
   assert json.loads(calls.read_text())==[expected,'--config',str(root/'factory-hosted-digest.json')],flag
   assert not result.stdout and not result.stderr
 print('actual workflow shell selects bounded App driver, original legacy CLI, and rejects invalid mode PASS')
PY
