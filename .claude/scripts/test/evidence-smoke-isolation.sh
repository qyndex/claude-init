#!/usr/bin/env bash
# Spec003 AC-21: actual collectors in separate repositories retain their own smoke.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PY'
import json,os,pathlib,shutil,subprocess,sys,tempfile,time
root=pathlib.Path(sys.argv[1]);global_smoke=pathlib.Path('/tmp/smoke.out')
assert not global_smoke.is_symlink(), 'refuse a symlink at the historical scratch path'
processes=[]
def wait_for(path,process):
 deadline=time.monotonic()+20
 while not path.exists():
  assert process.poll() is None,'collector exited before its smoke barrier'
  assert time.monotonic()<deadline,'smoke barrier deadline exceeded'
  time.sleep(.01)
def fixture(path,label,exit_code,hold):
 scripts=path/'.claude/scripts';(scripts/'lib').mkdir(parents=True);(path/'specs/active').mkdir(parents=True)
 for name in ['acceptance-criteria.py','collect-evidence.sh','spec-match.sh']:
  shutil.copy2(root/'.claude/scripts'/name,scripts/name)
 shutil.copy2(root/'.claude/scripts/lib/atomic-write.sh',scripts/'lib/atomic-write.sh')
 (path/'specs/active/900-isolation.md').write_text('# Fixture\n## Acceptance criteria\n- AC-1: retain current proof\n## Notes\n')
 date=subprocess.check_output(['date','+%Y-%m-%d'],text=True).strip();bundle=path/f'verify/{date}-900-isolation';bundle.mkdir(parents=True)
 (bundle/'results.json').write_text(json.dumps({'testResults':[{'assertionResults':[{'title':'AC-1 fixture','status':'passed'}]}]})+'\n')
 (scripts/'verify.sh').write_text('#!/usr/bin/env bash\nexec python3 .claude/scripts/smoke-fixture.py\n')
 (scripts/'smoke-fixture.py').write_text('''import os,pathlib,sys,time
print(os.environ['SMOKE_MARKER'],flush=True)
pathlib.Path('smoke-ready').touch()
if os.environ['SMOKE_HOLD']=='1':
 deadline=time.monotonic()+20
 while not pathlib.Path('smoke-release').exists():
  if time.monotonic()>deadline:sys.exit(99)
  time.sleep(.01)
sys.exit(int(os.environ['SMOKE_EXIT']))
''')
 for cmd in [['git','init','-q'],['git','config','user.name','Smoke fixture'],['git','config','user.email','fixture@example.invalid'],['git','add','specs'],['git','commit','-qm','test: initialize private fixture']]:
  subprocess.run(cmd,cwd=path,check=True,capture_output=True)
 env={**os.environ,'SMOKE_MARKER':label,'SMOKE_EXIT':str(exit_code),'SMOKE_HOLD':str(int(hold))}
 log=(path/'collector.log').open('w')
 process=subprocess.Popen(['bash',str(scripts/'collect-evidence.sh'),'900','--check-only'],cwd=path,env=env,stdout=log,stderr=subprocess.STDOUT)
 processes.append((process,log));return process,bundle
with tempfile.TemporaryDirectory(prefix='evidence-smoke-isolation-') as directory:
 scratch=pathlib.Path(directory);backup=scratch/'historical-smoke-preimage';existed=global_smoke.exists()
 if existed:shutil.copy2(global_smoke,backup)
 try:
  for number,(a_exit,b_exit) in enumerate([(17,0),(0,23)]):
   a=scratch/f'a-{number}';b=scratch/f'b-{number}'
   pa,ba=fixture(a,'FIXTURE_SMOKE_A',a_exit,True);wait_for(a/'smoke-ready',pa)
   pb,bb=fixture(b,'FIXTURE_SMOKE_B',b_exit,False);wait_for(b/'smoke-ready',pb)
   assert pb.wait(timeout=20)==(0 if b_exit==0 else 1),'B collector exit differs'
   (a/'smoke-release').touch();assert pa.wait(timeout=20)==(0 if a_exit==0 else 1),'A collector exit differs'
   for label,other,bundle,exit_code in [('FIXTURE_SMOKE_A','FIXTURE_SMOKE_B',ba,a_exit),('FIXTURE_SMOKE_B','FIXTURE_SMOKE_A',bb,b_exit)]:
    manifest=json.loads((bundle/'evidence.json').read_text());smoke=(bundle/'smoke.log').read_text()
    assert label in smoke and other not in smoke, 'cross-repository smoke output contamination: '+label
    assert 'exit: '+str(exit_code) in smoke and manifest['smoke_exit_max']==exit_code,'smoke exit changed'
    assert manifest['ac_proven']==1 and manifest['runner_exit']==0,'AC/runner contract changed'
    assert manifest['verdict']==('PASS' if exit_code==0 else 'FAIL'),'incorrect bundle verdict'
    attempt=bundle/next(p.name for p in bundle.iterdir() if p.is_dir() and p.name.startswith('attempt-'))
    assert 'AC-1 fixture' in (attempt/'results.json').read_text(),'raw AC proof missing'
  print('Evidence smoke isolation: 2 deterministic interleavings, 4 repository bundles PASS')
 finally:
  for process,log in processes:
   if process.poll() is None:process.kill()
   process.wait(timeout=25);log.close()
  if existed:shutil.copy2(backup,global_smoke)
  else:global_smoke.unlink(missing_ok=True)
PY
