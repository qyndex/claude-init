#!/usr/bin/env bash
# Spec014 AC-1 through AC-8: finite retained continuation and real recovery.
set -euo pipefail
cd "$(dirname "$0")/../../.."
"${FACTORY_TEST_PYTHON:-python3}" - <<'PY'
import hashlib,importlib.util,json,os,sys,time
from pathlib import Path
root=Path.cwd();scripts=root/'.claude/scripts'
def load(name,path):
 spec=importlib.util.spec_from_file_location(name,path)
 module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
preflight=load('continuation_preflight',scripts/'factory-preflight.py')
assert callable(getattr(preflight,'reporting_readiness',None)), 'retained continuation lacks actual read-only readiness composition'
proof=root/'verify/2026-10-17/T-290'
reuse=json.loads((proof/'runtime-reuse.json').read_text())
original=json.loads((proof/'runtime-result.json').read_text())
expected={'.claude/scripts/factory-runtime.py':'a69ec22bbd6fd9403cc70f93b3e2c38554603d97d99cdaf06df27f4470983f45',
 '.claude/scripts/test/factory-runtime.sh':'0cee0f6056f2783ac0f66e47b1b67946d123a916c54945c674d5c9d924679c5d'}
assert {row['path']:row['expected_sha256'] for row in reuse['checks']}==expected
for path,digest in expected.items():
 assert hashlib.sha256((root/path).read_bytes()).hexdigest()==digest,'runtime regression input changed: '+path
assert original['command']=='bash .claude/scripts/test/factory-runtime.sh' and type(original['exit_code']) is int and original['exit_code']==0
assert hashlib.sha256((proof/'runtime-result.log').read_bytes()).hexdigest()==original['log_sha256']=='8515fabf8c2cd1f651b3cdec47c2c404380227e60944a00bd92d1aa096be68d7'
bounded=load('continuation_bounded',scripts/'factory-bounded-process.py')
checks=('factory-reporting-rollover.sh','factory-receipt-readiness.sh',
        'factory-reporting-receipt-transfer.sh','factory-receipts-recovery.sh','factory-supervisor.sh')
start=time.monotonic();results=[]
for name in checks:
 command=['bash',str(scripts/'test'/name)]
 remaining=300-(time.monotonic()-start)
 assert remaining>0,'continuation aggregate 300-second bound exhausted'
 observed=bounded.run(command,env=dict(os.environ),cwd=root,timeout=remaining,max_timeout=300)
 print(observed.stdout.decode(),end='',flush=True)
 if observed.stderr:print(observed.stderr.decode(),file=sys.stderr,end='',flush=True)
 assert observed.returncode==0,'continuation check failed: '+name
 results.append({'command':'bash .claude/scripts/test/'+name,'exit_code':observed.returncode,
                 'test_sha256':hashlib.sha256((scripts/'test'/name).read_bytes()).hexdigest()})
assert time.monotonic()-start<300,'continuation aggregate exceeded 300 seconds'
print(json.dumps({'scope':'local retained continuation and actual process recovery',
 'checks':results,'runtime_reuse':expected,'elapsed_seconds':round(time.monotonic()-start,3),
 'native_app_private_cadence_cutover':'not_checked','all_history_complete':False,'task_credit':False},sort_keys=True))
PY
