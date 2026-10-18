#!/usr/bin/env bash
# Spec003 AC-21: actual collector + local consumer; runner/smoke are controlled fixtures.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PY'
import json,os,pathlib,shutil,subprocess,sys,tempfile
root=pathlib.Path(sys.argv[1]);passed=0;failures=[]
def proof(status='passed',label='original'):
 return json.dumps({'testResults':[{'assertionResults':[{'title':f'AC-1 {label}','status':status}]}]},separators=(',',':'))+'\n\n'
PASS=proof();FAIL=proof('failed');OTHER=proof('passed','replacement')
class Fixture:
 def __init__(self,path):
  self.path=path;self.scripts=path/'.claude/scripts';(self.scripts/'lib').mkdir(parents=True);(path/'specs/active').mkdir(parents=True);(path/'bin').mkdir()
  for name in ['acceptance-criteria.py','collect-evidence.sh','spec-match.sh','check-local-evidence.py','validate-candidate-evidence.py']:shutil.copy2(root/'.claude/scripts'/name,self.scripts/name)
  shutil.copy2(root/'.claude/scripts/lib/atomic-write.sh',self.scripts/'lib/atomic-write.sh')
  (path/'specs/active/900-fixture.md').write_text('# Fixture\n## Acceptance criteria\n- AC-1: original behavior\n## Notes\n')
  (path/'playwright.config.ts').write_text('// adopter configuration must remain unchanged\n')
  (self.scripts/'verify.sh').write_text('#!/usr/bin/env bash\nexec python3 .claude/scripts/fixture-smoke.py\n')
  (self.scripts/'fixture-smoke.py').write_text('''import os,pathlib,sys
p=pathlib.Path(os.environ['FIXTURE_BUNDLE']);replacement=pathlib.Path(os.environ['FIXTURE_REPLACEMENT']).read_bytes()
(p/'smoke-ran').write_text('yes')
if os.environ.get('FIXTURE_DELETE_ROOT')=='1':(p/'results.json').unlink(missing_ok=True)
else:(p/'results.json').write_bytes(replacement)
if os.environ.get('FIXTURE_TAMPER_SNAPSHOT')=='1':
 for result in p.glob('attempt-*/results.json'):result.write_bytes(replacement)
sys.exit(int(os.environ.get('FIXTURE_SMOKE_EXIT','0')))
''')
  npx=path/'bin/npx';npx.write_text('''#!/usr/bin/env python3
import json,os,pathlib,sys
output=[arg.split('=',1)[1] for arg in sys.argv[1:] if arg.startswith('--outputFile=')]
assert len(output)==1
pathlib.Path(output[0]).write_bytes(pathlib.Path(os.environ['FIXTURE_RUNNER_PROOF']).read_bytes())
pathlib.Path('runner-call.json').write_text(json.dumps(sys.argv[1:]))
sys.exit(int(os.environ.get('FIXTURE_RUNNER_EXIT','0')))
''');npx.chmod(0o755)
  date=subprocess.check_output(['date','+%Y-%m-%d'],text=True).strip();self.bundle=path/f'verify/{date}-900-fixture';self.bundle.mkdir(parents=True)
  for cmd in [['git','init','-q'],['git','config','user.name','Evidence fixture'],['git','config','user.email','fixture@example.invalid'],['git','add','specs'],['git','commit','-qm','test: initialize private evidence fixture']]:subprocess.run(cmd,cwd=path,check=True,capture_output=True)
  self.env={**os.environ,'PATH':str(path/'bin')+os.pathsep+os.environ['PATH'],'FIXTURE_BUNDLE':str(self.bundle),'FIXTURE_REPLACEMENT':str(path/'replacement.json'),'FIXTURE_RUNNER_PROOF':str(path/'runner.json')}
 def run(self,initial,replacement=OTHER,normal=False,**extra):
  result=self.bundle/'results.json'
  if initial is None:result.unlink(missing_ok=True)
  else:result.write_text(initial)
  (self.path/'replacement.json').write_text(replacement);(self.path/'runner.json').write_text(PASS)
  if normal:(self.path/'package.json').write_text('{"devDependencies":{"jest":"controlled-fixture"}}')
  self.env.update(extra)
  command=['bash',str(self.scripts/'collect-evidence.sh'),'900']+([] if normal else ['--check-only'])
  return subprocess.run(command,cwd=self.path,env=self.env,text=True,capture_output=True)
 def manifest(self):return json.loads((self.bundle/'evidence.json').read_text())
 def consumed(self):
  value=self.manifest()['results_file'];path=self.path/value
  assert path.is_relative_to(self.bundle) and path.parent.name.startswith('attempt-'),value
  return path
 def consumer(self):
  changed=self.path/'changed.txt';changed.write_text('specs/active/900-fixture.md\n'+str((self.bundle/'evidence.json').relative_to(self.path))+'\n')
  return subprocess.run([sys.executable,str(self.scripts/'check-local-evidence.py'),'--root',str(self.path),'--changed-files',str(changed),'--output-paths',str(self.path/'outputs.txt')],cwd=self.path,text=True,capture_output=True)
def case(label,action):
 global passed
 with tempfile.TemporaryDirectory(prefix='evidence-proof-preservation-') as folder:
  fixture=Fixture(pathlib.Path(folder))
  try:action(fixture);passed+=1
  except (AssertionError,KeyError,FileNotFoundError,json.JSONDecodeError) as error:failures.append(f'{label}: {error}')
def valid(f,replacement,**extra):
 result=f.run(PASS,replacement,**extra);assert result.returncode==0,result.stdout[-400:]+result.stderr[-400:]
 assert f.manifest()['verdict']=='PASS'
 assert f.consumed().read_text()==PASS,'consumed proof changed from original bytes'
 assert (f.bundle/'results.json').read_text()==PASS,'canonical proof not restored from original'
 consumer=f.consumer();assert consumer.returncode==0,consumer.stdout+consumer.stderr
 assert (f.path/'playwright.config.ts').read_text()=='// adopter configuration must remain unchanged\n'
for label,replacement in [('smoke-FAIL',FAIL),('smoke-malformed','not JSON'),('smoke-other-PASS',OTHER)]:case(label,lambda f,r=replacement:valid(f,r))
case('smoke-deletes-root',lambda f:valid(f,OTHER,FIXTURE_DELETE_ROOT='1'))
def invalid(f,initial,early=False):
 result=f.run(initial,OTHER);assert result.returncode!=0,'invalid/missing/failing original became PASS'
 if early:assert not (f.bundle/'smoke-ran').exists(),'invalid original reached smoke'
 if (f.bundle/'evidence.json').exists():assert f.manifest()['verdict']=='FAIL'
 assert f.consumer().returncode!=0,'downstream accepted unproven original'
for label,initial,early in [('failed-original',FAIL,False),('missing-original',None,False),('malformed-original','not JSON',True),('trailing-garbage',PASS+'trailing',True),('non-json-number',PASS.rstrip()[:-1]+',"number":NaN}',True),('nul-trailing',PASS+'\x00',True),('nul-junk',PASS+'\x00junk',True),('empty-original','',True),('array-original','[]',True)]:case(label,lambda f,i=initial,e=early:invalid(f,i,e))
def smoke_failure(f):
 result=f.run(PASS,OTHER,FIXTURE_SMOKE_EXIT='17');assert result.returncode!=0
 assert f.manifest()['smoke_exit_max']==17 and f.consumer().returncode!=0
case('smoke-failure-remains-failure',smoke_failure)
def normal(f,runner_exit='0'):
 result=f.run(FAIL,FAIL,normal=True,FIXTURE_RUNNER_EXIT=runner_exit)
 assert (f.path/'runner-call.json').is_file(),'controlled runner was not invoked'
 assert f.consumed().read_text()==PASS,'normal attempt did not preserve runner proof'
 assert (f.bundle/'results.json').read_text()==PASS,'normal canonical publication is stale'
 assert (result.returncode==0)==(runner_exit=='0')
 assert (f.consumer().returncode==0)==(runner_exit=='0')
case('normal-isolation-and-consumer',normal)
case('normal-failed-runner-remains-failure',lambda f:normal(f,'42'))
def tamper(f):
 result=f.run(FAIL,OTHER,FIXTURE_TAMPER_SNAPSHOT='1');assert result.returncode!=0,'smoke replaced failing snapshot with PASS'
 assert not (f.bundle/'evidence.json').exists(),'tampered snapshot published a manifest'
 assert f.consumer().returncode!=0
case('snapshot-tamper-blocks',tamper)
def repeated(f):
 first=f.run(PASS,FAIL);assert first.returncode==0,first.stdout
 first_path=f.consumed();assert first_path.read_text()==PASS
 second=f.run(FAIL,OTHER);assert second.returncode!=0,'second run reused old passing snapshot'
 assert f.consumed()!=first_path and f.consumed().read_text()==FAIL
 assert first_path.read_text()==PASS,'prior proof artifact was overwritten'
 assert f.consumer().returncode!=0
case('repeated-attempts-do-not-reuse-proof',repeated)
def isolated_integrity_imports(f,module):
 marker=f.path/'shadow-imported'
 (f.path/(module+'.py')).write_text('from pathlib import Path\nPath('+repr(str(marker))+').write_text("unexpected checkout import")\nraise RuntimeError("checkout module must not run in proof integrity path")\n')
 valid(f,OTHER)
 assert not marker.exists(),'checkout-controlled module entered proof integrity path'
for module in ['json','hashlib']:case('isolated-integrity-'+module,lambda f,m=module:isolated_integrity_imports(f,m))
template=(root/'.claude/templates/evidence/playwright.config.ts').read_text().split('import {',1)[0]
try:
 assert 'Copy to repo root as playwright.evidence.config.ts.' in template
 assert '--config playwright.evidence.config.ts e2e/042' in template
 assert 'e2e/<spec-id>/' in template
 passed+=1
except AssertionError:failures.append('template guidance does not match evidence config/journey directory contract')
print(f'Evidence proof preservation: {passed} passed; {len(failures)} failed')
for failure in failures:print('FAIL '+failure)
assert not failures,'\n'.join(failures)
PY
