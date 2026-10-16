#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-5: exact administrative observation, never candidate or native proof."""
import copy,datetime,hashlib,importlib.util,json,tempfile,os,subprocess
from pathlib import Path
p=Path('.claude/scripts/factory-policy-observation.py')
s=importlib.util.spec_from_file_location('observation',p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
now=datetime.datetime(2026,10,16,12,tzinfo=datetime.timezone.utc)
repo={'id':42,'full_name':'qyndex/claude-init'}
rules={'id':7,'node_id':'R_7','name':'main','source':'qyndex/claude-init','source_type':'Repository','target':'branch','enforcement':'active','created_at':'2026-10-15T00:00:00Z','updated_at':'2026-10-16T11:58:00Z','conditions':{'ref_name':{'include':['refs/heads/main'],'exclude':[]}},'rules':[{'type':'pull_request'}],'bypass_actors':[],'_links':{'self':{'href':'https://api.github.com/repos/qyndex/claude-init/rulesets/7'}}}
count=0
def ok(fn):
 global count
 fn();count+=1
def bad(fn):
 global count
 try:fn()
 except ValueError:count+=1;return
 raise AssertionError('invalid observation accepted')
ob=m.capture(repo,rules,now=now)
hidden=copy.deepcopy(rules);hidden.pop('bypass_actors')
ok(lambda:m.validate(repo,rules,None,now=now))
ok(lambda:m.validate(repo,hidden,ob,now=now))
for actors in (None,{},'',[{'actor_id':1}],False):
 b=copy.deepcopy(rules);b['bypass_actors']=actors;bad(lambda b=b:m.validate(repo,b,ob,now=now))
for field,value in [('repository_id',43),('repository','evil/repo'),('ruleset_id',8),('metadata_sha256','0'*64),('updated_at','2026-10-16T11:57:00Z'),('observed_at','2026-10-16T12:00:01Z'),('observed_at','2026-10-16T11:58:59Z'),('observed_at','2026-10-16T11:58:00Z'),('schema_version',True),('bypass_actors',[{'actor_id':1}]),('bypass_actors',None),('extra','x')]:
 b=dict(ob);b[field]=value;bad(lambda b=b:m.validate(repo,hidden,b,now=now))
for key in ob:
 b=dict(ob);b.pop(key);bad(lambda b=b:m.validate(repo,hidden,b,now=now))
for key in ('rules','conditions','updated_at','id','source','target','enforcement'):
 b=copy.deepcopy(hidden);b.pop(key);bad(lambda b=b:m.validate(repo,b,ob,now=now))
b=copy.deepcopy(hidden);b['rules']=[{'type':'deletion'}];bad(lambda:m.validate(repo,b,ob,now=now))
b=copy.deepcopy(hidden);b['_links']['self']['href']='https://foreign.invalid';ok(lambda:m.validate(repo,b,ob,now=now))
bad(lambda:m.capture(repo,hidden,now=now))
bad(lambda:m.capture(repo,rules,now=now-datetime.timedelta(seconds=61)))
bad(lambda:m.validate(repo,hidden,None,now=now))
for raw in ('{"a":1,"a":2}','NaN','{"x":NaN}', '[]','x'*(m.MAX_BYTES+1)):
 bad(lambda raw=raw:m.decode(raw.encode()))
ok(lambda: m.decode(json.dumps(ob).encode()))
class API:
 def __init__(self):self.calls=[]
 def get(self,path):
  self.calls.append(path)
  return repo if path=='repos/qyndex/claude-init' else rules
api=API();ok(lambda:m.observe(api,'qyndex/claude-init',7,now=now));assert api.calls==['repos/qyndex/claude-init','repos/qyndex/claude-init/rulesets/7']
for name in ('https://evil.invalid','qyndex/../evil','qyndex/repo?x=1'):
 bad(lambda name=name:m.observe(api,name,7,now=now))
bad(lambda:m.observe(api,'qyndex/claude-init',True,now=now))
class Foreign(API):
 def get(self,path):return dict(repo,full_name='evil/repo') if path.endswith('claude-init') else rules
bad(lambda:m.observe(Foreign(),'qyndex/claude-init',7,now=now))
# Fractional timezone data must retain subsecond precision, not truncate settle time.
fractional=copy.deepcopy(rules);fractional['updated_at']='2026-10-16T22:59:00.995+11:00'
bad(lambda:m.capture(repo,fractional,now=now))
ok(lambda:m.capture(repo,fractional,now=now+datetime.timedelta(seconds=1)))
# Actual bounded transport against a disposable gh executable: fixed GET only.
with tempfile.TemporaryDirectory() as directory:
 gh=Path(directory)/'gh';trace=Path(directory)/'args.json'
 gh.write_text('#!/usr/bin/env python3\nimport json,sys\nfrom pathlib import Path\nPath('+repr(str(trace))+').write_text(json.dumps(sys.argv[1:]))\nprint('+repr(json.dumps(repo))+')\n')
 gh.chmod(0o755)
 previous=os.environ['PATH'];os.environ['PATH']=directory+os.pathsep+previous
 try:
  ok(lambda: m.GitHub().get('repos/qyndex/claude-init'))
  assert json.loads(trace.read_text())==['api','--hostname','github.com','--method','GET','repos/qyndex/claude-init']
  gh.write_text('#!/usr/bin/env python3\nprint("x"*300000)\n')
  bad(lambda:m.GitHub().get('repos/qyndex/claude-init'))
 finally:os.environ['PATH']=previous
for key in ('id','full_name'):
 b=dict(repo);b.pop(key);bad(lambda b=b:m.validate(b,hidden,ob,now=now))
for key,value in [('id',True),('full_name','qyndex/../evil')]:
 b=dict(repo);b[key]=value;bad(lambda b=b:m.validate(b,hidden,ob,now=now))
b=copy.deepcopy(hidden);b['unknown_policy_field']=1;bad(lambda:m.validate(repo,b,ob,now=now))
print(f'{count} policy observation cases PASS (AC-5); transport fixture only, no live operator observation')
PY
