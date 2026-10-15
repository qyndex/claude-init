#!/usr/bin/env bash
# AC-12 combined assessment output budget; AC-10 timeout cleanup
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PY'
import importlib.util,inspect,os,sys,tempfile,subprocess
from pathlib import Path
s=importlib.util.spec_from_file_location('bounded',Path(sys.argv[1])/'.claude/scripts/factory-bounded-process.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
assert 'aggregate_limit' in inspect.signature(m.run).parameters,'aggregate Scout output bound absent'
with tempfile.TemporaryDirectory() as d:
 def run(code,**kw):return m.run([sys.executable,'-c',code],env={'PATH':os.defpath},cwd=d,timeout=1,**kw)
 # A real split-stream process must be rejected by the combined cap.
 try:run('import os;os.write(1,b"a"*40000);os.write(2,b"b"*40000)',aggregate_limit=65536)
 except ValueError as e:assert 'aggregate' in str(e),str(e)
 else:raise AssertionError('aggregate Scout output bound absent')
 good=run('import os;os.write(1,b"a"*32768);os.write(2,b"b"*32768)',aggregate_limit=65536)
 assert good.returncode==0 and len(good.stdout)+len(good.stderr)==65536
 legacy=run('import os;os.write(1,b"a"*40000);os.write(2,b"b"*40000)',limit=65536)
 assert len(legacy.stdout)+len(legacy.stderr)==80000
 for value in [True,0,-1,1023,8000001,'65536']:
  try:run('raise SystemExit(0)',aggregate_limit=value)
  except ValueError:pass
  else:raise AssertionError('invalid combined cap accepted')
 pid=Path(d)/'descendant.pid'
 try:run('import os,time;from pathlib import Path;p=os.fork();Path('+repr(str(pid))+').write_text(str(p)) if p else time.sleep(10)',aggregate_limit=65536)
 except ValueError as e:assert 'timeout' in str(e)
 else:raise AssertionError('descendant-held EOF ignored')
 assert pid.exists()
 observed=subprocess.run(['ps','-p',pid.read_text(),'-o','stat='],capture_output=True,text=True)
 assert not observed.stdout.strip() or observed.stdout.strip().startswith('Z'),observed.stdout
 print('combined output boundary, legacy limits, invalid bounds and descendant cleanup passed')
PY
