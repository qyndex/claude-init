#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-6/AC-7: reviewed bootstrap anchors, exclusive writer and honest coverage."""
import pathlib,tempfile,json,subprocess,copy,importlib.util,datetime
s=importlib.util.spec_from_file_location('archive','.claude/scripts/factory-receipt-archive.py');a=importlib.util.module_from_spec(s);s.loader.exec_module(a)
count=0
with tempfile.TemporaryDirectory() as tmp:
 root=pathlib.Path(tmp);gitroot=root/'state';gitroot.mkdir()
 def git(*args):return subprocess.check_output(['git','-C',str(gitroot),*args],stderr=subprocess.PIPE).decode().strip()
 git('init','-q');git('config','user.name','Fixture');git('config','user.email','fixture@example.invalid');(gitroot/'README.md').write_text('reviewed bootstrap');git('add','.');git('commit','-qm','bootstrap');bootstrap=git('rev-parse','HEAD');btree=git('rev-parse','HEAD^{tree}')
 (gitroot/'reports').mkdir();(gitroot/'reports'/('a'*64+'.json')).write_text('{}');git('add','.');git('commit','-qm','protected append');head=git('rev-parse','HEAD')
 branch='reporting-state';app=7;now=datetime.datetime(2026,10,16,0,0,tzinfo=datetime.timezone.utc)
 def policy(identity,rules,bypass):return {'id':identity,'source':'org/repo','source_type':'Repository','target':'branch','enforcement':'active','conditions':{'ref_name':{'include':['refs/heads/'+branch],'exclude':[]}},'rules':[{'type':r} for r in rules],'bypass_actors':bypass,'updated_at':'2026-10-15T00:00:00Z'}
 policies={1:policy(1,['update'],[{'actor_id':app,'actor_type':'Integration','bypass_mode':'always'}]),2:policy(2,['non_fast_forward','deletion'],[])}
 class API:
  repo='org/repo'
  calls=[]
  def request(self,path,method='GET',payload=None):
   assert method=='GET' and payload is None;self.calls.append(path)
   if path=='repos/org/repo':return {'id':101,'full_name':self.repo,'private':False,'archived':False,'default_branch':'main'}
   if '/rules/branches/' in path:return [{'type':r['type'],'ruleset_id':i} for i,p in policies.items() for r in p['rules']]
   if '/rulesets/' in path:return policies[int(path.rsplit('/',1)[1])]
   if '/git/ref/' in path:return {'ref':'refs/heads/'+branch,'object':{'type':'commit','sha':head}}
   if '/git/commits/' in path:
    sha=path.rsplit('/',1)[1];parts=git('show','-s','--format=%T %P',sha).split();return {'sha':sha,'tree':{'sha':parts[0]},'parents':[{'sha':p} for p in parts[1:]]}
   if '/git/trees/' in path:
    tree=path.rsplit('/',1)[1].split('?')[0];rows=[]
    for line in git('ls-tree',tree).splitlines():
     mode,kind,rest=line.split(' ',2);sha,name=rest.split('\t');rows.append({'mode':mode,'type':kind,'sha':sha,'path':name, **({'size':int(git('cat-file','-s',sha))} if kind=='blob' else {})})
    return {'sha':tree,'truncated':False,'tree':rows}
   raise AssertionError(path)
 approval={'schema_version':1,'repository':'org/repo','repository_id':101,'private':False,'branch':branch,'bootstrap_sha':bootstrap,'bootstrap_tree':btree,'coverage_from':'2026-10-16T00:00:00Z','observed_at':'2026-10-16T00:00:00Z','writer_app_id':app,'policies':{str(i):a.digest(a.canonical(p)) for i,p in policies.items()}}
 path=root/'receipt-bootstrap.json'
 def run():path.write_text(json.dumps(approval));return a.verify_bootstrap(API(),path,now=now)
 result=run();assert result['head']==head and result['bootstrap_sha']==bootstrap;count+=1
 def reject(fn,reason):
  global count
  try:fn()
  except ValueError as e:assert reason in str(e),(reason,str(e));count+=1
  else:raise AssertionError('accepted '+reason)
 original=copy.deepcopy(approval)
 for key,value,reason in [('repository_id',102,'repository'),('private',True,'repository'),('branch','main','default branch'),('bootstrap_sha','f'*40,'bootstrap'),('bootstrap_tree','f'*40,'bootstrap'),('coverage_from','2026-10-17T00:00:00Z','coverage')]:
  approval[key]=value;reject(run,reason);approval.clear();approval.update(copy.deepcopy(original))
 policies[1]['bypass_actors'][0]['actor_id']=8;reject(run,'policy changed');policies[1]['bypass_actors'][0]['actor_id']=app
 approval['policies']['1']=a.digest(a.canonical(policies[1]));policies[1]['rules'].append({'type':'deletion'});approval['policies']['1']=a.digest(a.canonical(policies[1]));reject(run,'update-only');policies[1]['rules'].pop();approval.clear();approval.update(copy.deepcopy(original))
 policies[2]['bypass_actors']=[{'actor_id':app,'actor_type':'Integration','bypass_mode':'always'}];approval['policies']['2']=a.digest(a.canonical(policies[2]));reject(run,'no-bypass');policies[2]['bypass_actors']=[];approval.clear();approval.update(copy.deepcopy(original))
 class OversizedAPI(API):
  def request(self,name,method='GET',payload=None):
   value=super().request(name,method,payload)
   return dict(value,untrusted='x'*1048576) if name=='repos/org/repo' else value
 path.write_text(json.dumps(approval));reject(lambda:a.verify_bootstrap(OversizedAPI(),path,now=now),'response bound')
 saved=policies.pop(1);savedapproval=approval['policies'].pop('1');reject(run,'exclusive writer');policies[1]=saved;approval['policies']['1']=savedapproval
 assert a.coverage_status(result,'2026-10-15T23:59:59Z',available=False)['status']=='outside-coverage';count+=1
 assert a.coverage_status(result,'2026-10-16T00:00:00Z',available=False)['status']=='gap';count+=1
 assert a.coverage_status(result,'2026-10-16T00:00:00Z',available=True)['status']=='complete';count+=1
 print(f'{count} bootstrap/coverage cases passed with real disposable Git ancestry; no live bootstrap')
PY
