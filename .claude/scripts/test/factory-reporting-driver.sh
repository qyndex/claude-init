#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-7/AC-8: real fixed child processes, actual routed head observer, no live APIs."""
import json,os,shutil,subprocess,sys,tempfile,time
from pathlib import Path
root=Path.cwd();assert (root/'.claude/scripts/factory-reporting-driver.py').is_file(),'missing bounded fixed reporting job driver'
checks=0
with tempfile.TemporaryDirectory() as temporary:
 base=Path(temporary).resolve()
 def fixture(name,steps):
  dest=base/name;dest.mkdir();scripts=dest/'.claude/scripts';scripts.parent.mkdir()
  shutil.copytree(root/'.claude/scripts',scripts,ignore=shutil.ignore_patterns('test','__pycache__'))
  original=scripts/'factory-git-state.py';original.rename(scripts/'factory-git-state-library.py')
  original.write_text('''import json,os,runpy,sys,time,subprocess
from pathlib import Path
library=runpy.run_path(str(Path(__file__).with_name('factory-git-state-library.py')))
globals().update({k:v for k,v in library.items() if not k.startswith('__')})
if __name__=='__main__':
 state=Path(os.environ['FIXTURE_STATE']);calls=state/'calls';old=calls.read_text().splitlines() if calls.exists() else [];index=len(old)
 with calls.open('a') as stream:stream.write(str(os.getpid())+'\\n')
 steps=json.loads((state/'steps').read_text());step=steps[min(index,len(steps)-1)]
 if step.get('progress'):(state/'head').write_text(format(index+2,'040x'))
 if step.get('change_source'):Path(__file__).with_name('factory-git-state-library.py').write_text('# changed')
 if step.get('change_head'):subprocess.run(['git','-C',str(Path(__file__).resolve().parents[2]),'commit','--allow-empty','-qm','changed head'],check=True,capture_output=True)
 time.sleep(step.get('sleep',0))
 sys.stdout.write(step.get('stdout',json.dumps({'status':step.get('status','incomplete'),'phase':'review'})))
 sys.stderr.write(step.get('stderr',''))
 sys.exit(step.get('rc',0))
''')
  state=base/(name+'-private');state.mkdir();(state/'steps').write_text(json.dumps(steps));(state/'head').write_text('1'*40)
  config=state/'config.json';config.write_text(json.dumps({'repository':'org/repo','state_repository':'org/repo','state_branch':'state'}))
  bins=state/'bin';bins.mkdir();provider=bins/'gh';provider.write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
state=Path(os.environ['HOME']);assert os.environ['GH_TOKEN']=='synthetic-writer'
assert sys.argv[1:6]==['api','--hostname','github.com','--method','GET']
assert sys.argv[6]=='repos/org/repo/git/ref/heads/state'
with (state/'observer').open('a') as stream:stream.write('GET\\n')
if (state/'provider-error').exists():sys.stderr.write('Retry-After: 60');sys.exit(1)
print(json.dumps({'ref':'refs/heads/state','object':{'type':'commit','sha':(state/'head').read_text()}}))
''');provider.chmod(0o755)
  def git(*args):return subprocess.check_output(['git','-C',str(dest),*args],stderr=subprocess.DEVNULL,text=True).strip()
  git('init','-q');git('config','user.name','Fixture');git('config','user.email','fixture@example.invalid');git('add','.');git('commit','-qm','fixed fixture')
  env={'PATH':str(bins)+os.pathsep+os.environ['PATH'],'HOME':str(state),'FIXTURE_STATE':str(state),'GITHUB_SHA':git('rev-parse','HEAD'),'GITHUB_REPOSITORY':'org/repo','FACTORY_REPORTING_STATE_REPOSITORY':'org/repo','GH_TOKEN':'synthetic-source','FACTORY_REPORTING_APP_TOKEN':'synthetic-writer','FACTORY_REPORTING_APP_ID':'7','FACTORY_REPORTING_APP_WRITER_ENABLED':'true'}
  return scripts,state,config,env
 def invoke(data,*,seconds=120,limit=16,change=None):
  scripts,state,config,env=data;env=dict(env,**(change or {}));start=time.monotonic()
  result=subprocess.run([sys.executable,'-I',str(scripts/'factory-reporting-driver.py'),'--config',str(config),'--max-seconds',str(seconds),'--max-invocations',str(limit)],env=env,capture_output=True,text=True,timeout=15)
  assert 'PRIVATE-SENTINEL' not in result.stdout+result.stderr
  return result,time.monotonic()-start
 def count(data):
  path=data[1]/'calls';return len(path.read_text().splitlines()) if path.exists() else 0
 data=fixture('progress',[{'progress':True}]*3+[{'status':'delivered'}]);result,_=invoke(data);assert result.returncode==0,result.stderr;doc=json.loads(result.stdout);assert doc['status']=='delivered' and doc['invocations']==4 and doc['observer_calls']==3 and not doc['child_api_counters_available'],doc;assert len(set((data[1]/'calls').read_text().splitlines()))==4;checks+=1
 data=fixture('stalled',[{}]);result,_=invoke(data);doc=json.loads(result.stdout);assert doc['reason']=='no-state-progress' and count(data)==4;checks+=1
 for label,step in [('error',{'rc':42,'stderr':'PRIVATE-SENTINEL'}),('backoff',{'rc':43,'stderr':'PRIVATE-SENTINEL Retry-After: 60'}),('uncertain',{'status':'uncertain'}),('malformed',{'stdout':'PRIVATE-SENTINEL'})]:
  data=fixture(label,[step]);result,_=invoke(data);assert result.returncode==1 and count(data)==1,(label,result.stdout,result.stderr);checks+=1
 data=fixture('restart',[{'progress':True},{'status':'delivered'}]);first,_=invoke(data,limit=1);assert json.loads(first.stdout)['reason']=='job-invocation-limit';second,_=invoke(data);assert json.loads(second.stdout)['status']=='delivered' and count(data)==2;checks+=1
 data=fixture('provider-backoff',[{}]);(data[1]/'provider-error').touch();result,_=invoke(data);assert result.returncode==1 and count(data)==1;checks+=1
 data=fixture('source-changed',[{'progress':True,'change_source':True}]);result,_=invoke(data);assert result.returncode==1 and count(data)==1;checks+=1
 data=fixture('head-changed',[{'progress':True,'change_head':True}]);result,_=invoke(data);assert result.returncode==1 and count(data)==1;checks+=1
 data=fixture('deadline',[{'sleep':120}]);result,elapsed=invoke(data,seconds=2);assert result.returncode==0 and json.loads(result.stdout)['reason']=='child-timeout' and count(data)==1 and elapsed<8,(result.stdout,result.stderr,elapsed)
 pid=int((data[1]/'calls').read_text());
 try:os.kill(pid,0)
 except ProcessLookupError:pass
 else:raise AssertionError('timed out reporting child remains live')
 checks+=1
 data=fixture('off',[{'rc':42,'stdout':'legacy output','stderr':'legacy stderr'}]);result,_=invoke(data,change={'FACTORY_REPORTING_APP_WRITER_ENABLED':'false','FACTORY_REPORTING_STATE_REPOSITORY':'other/state','FACTORY_REPORTING_APP_TOKEN':''});assert result.returncode==42 and result.stdout=='legacy output' and result.stderr=='legacy stderr' and count(data)==1 and not (data[1]/'observer').exists();checks+=1
 data=fixture('invalid-flag',[{}]);result,_=invoke(data,change={'FACTORY_REPORTING_APP_WRITER_ENABLED':'TRUE'});assert result.returncode==1 and count(data)==0;checks+=1
 data=fixture('invalid-bound',[{}]);result,_=invoke(data,limit=513);assert result.returncode==1 and count(data)==0;checks+=1
print(str(checks)+' real-process bounded reporting driver cases passed; fixture CLI and local gh provider only')
PY
