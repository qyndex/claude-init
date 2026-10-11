#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PY'
import copy,json,os,subprocess,sys,tempfile
from pathlib import Path
root=Path(sys.argv[1])
with tempfile.TemporaryDirectory() as folder:
 base=Path(folder).resolve();bin=base/'bin';bin.mkdir();calls=base/'calls.jsonl';livefile=base/'live.json';branches=base/'branches.json'
 gh=bin/'gh';gh.write_text('#!'+sys.executable+'\n'+"import json,os,sys\nfrom pathlib import Path\nargs=sys.argv[1:]\nassert len(args)==4 and args[0]=='api' and args[2:]==['--method','GET'],args\nwith open(os.environ['CALLS'],'a') as f:f.write(json.dumps(args)+'\\n')\npath=args[1]\nassert path in ['repos/adopter/project/rules/branches/release%2Fmain','repos/adopter/project/rulesets/73'],path\nprint(Path(os.environ['BRANCHES'] if '/rules/branches/' in path else os.environ['LIVE']).read_text())\n");gh.chmod(0o755)
 env=dict(os.environ,PATH=str(bin)+os.pathsep+os.defpath,CALLS=str(calls),LIVE=str(livefile),BRANCHES=str(branches))
 policy={'repository':'adopter/project','base_branch':'release/main','app_id':555,'required_checks':{'review':17,'security-review':19,'factory-verification':23,'factory-independent-review':29,'Custom / lint (Linux)':37}}
 live={'id':73,'name':'existing','target':'branch','enforcement':'active','bypass_actors':[],'conditions':{'ref_name':{'include':['refs/heads/release/main'],'exclude':[]}},'rules':[{'type':'pull_request','parameters':{'required_approving_review_count':2,'required_review_thread_resolution':True}},{'type':'required_status_checks','parameters':{'strict_required_status_checks_policy':True,'do_not_enforce_on_create':True,'required_status_checks':[{'context':'unrelated','integration_id':31},{'context':'review','integration_id':None}]}},{'type':'deletion'}]}
 policyfile=base/'policy.json';output=base/'proposal.json'
 def write(p=policy,l=live,applicable=True):
  policyfile.write_text(json.dumps(p));livefile.write_text(json.dumps(l));branches.write_text(json.dumps([{'type':'required_status_checks','ruleset_id':73 if applicable else 74}]))
 def run():return subprocess.run([sys.executable,str(root/'.claude/scripts/factory-ruleset-plan.py'),'--policy',str(policyfile),'--ruleset-id','73','--app-id','555','--output',str(output)],env=env,cwd=root,capture_output=True,text=True)
 write();result=run();assert result.returncode==0,'generic policy-bound planning failed: '+result.stdout+result.stderr
 proposal=json.loads(output.read_text());assert proposal['rules'][0]==live['rules'][0] and proposal['rules'][2]==live['rules'][2] and proposal['conditions']==live['conditions']
 checks=proposal['rules'][1]['parameters']['required_status_checks'];pins={c['context']:c['integration_id'] for c in checks}
 assert pins==dict(policy['required_checks'],unrelated=31,**{'factory-eligibility':555})
 assert proposal['rules'][1]['parameters']['do_not_enforce_on_create'] is True
 assert json.loads(calls.read_text().splitlines()[0])[1]=='repos/adopter/project/rules/branches/release%2Fmain'
 second=copy.deepcopy(proposal);second['id']=73;write(l=second);result=run();assert result.returncode==0 and json.loads(output.read_text())==proposal
 print('AC-1/AC-2: actual GET-only generic repository/branch selection, complete checks, preservation and idempotence passed')
 def rejects(p=policy,l=live,applicable=True):
  output.write_text('preserve');write(p,l,applicable);result=run();assert result.returncode!=0 and output.read_text()=='preserve',result.stdout+result.stderr
 for field,value in [('repository','bad/repo/extra'),('repository','../project'),('base_branch',''),('app_id',556),('required_checks',{}),('required_checks',{'review':True})]:
  p=copy.deepcopy(policy);p[field]=value;rejects(p=p)
 for field,value in [('target','tag'),('id',74),('enforcement','disabled'),('bypass_actors',[{'actor_id':1}])]:
  l=copy.deepcopy(live);l[field]=value;rejects(l=l)
 rejects(applicable=False)
 l=copy.deepcopy(live);l['rules'][1]['parameters']['strict_required_status_checks_policy']=False;rejects(l=l)
 l=copy.deepcopy(live);l['rules'].append(copy.deepcopy(l['rules'][1]));rejects(l=l)
 l=copy.deepcopy(live);l['rules'][1]['parameters']['required_status_checks'].append({'context':'review','integration_id':17});rejects(l=l)
 l=copy.deepcopy(live);l['rules'][1]['parameters']['required_status_checks'][1]['integration_id']=99;rejects(l=l)
 l=copy.deepcopy(live);l['rules'][1]['parameters']['required_status_checks'].append({'context':'factory-eligibility','integration_id':99});rejects(l=l)
 l=copy.deepcopy(live);l['rules'][1]['parameters']['required_status_checks'][0]['integration_id']=True;rejects(l=l)
 print('AC-3: malformed, foreign, bypass, nonstrict, duplicate and conflicting inputs preserve output and block')
workflow=(root/'.github/workflows/claude-security.yml').read_text()
types=workflow.split('types:',1)[1].split('\n',1)[0];assert 'synchronize' in types,'security misses updated PR heads'
assert 'cancel-in-progress: true' in workflow and "github.event.pull_request.draft == false" in workflow
print('AC-4: security synchronize retains concurrency and exemptions; live pause is unchanged')
PY
bash "$ROOT/.claude/scripts/test/factory-workflow-baseline.sh"
bash "$ROOT/.claude/scripts/test/factory-coordinator.sh"
bash "$ROOT/.claude/scripts/test/autonomous-ship.sh"
