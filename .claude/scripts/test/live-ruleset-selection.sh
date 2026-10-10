#!/usr/bin/env bash
# Execute the actual workflow drift step with injected gh responses.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PYTEST'
import json,os,pathlib,subprocess,sys,tempfile
root=pathlib.Path(sys.argv[1]);workflow=(root/'.github/workflows/harness-validate.yml').read_text()
block=workflow.split('      - name: Live ruleset drift',1)[1].split('        run: |',1)[1]
script='\n'.join(line[10:] for line in block.splitlines()[1:] if line.startswith('          ')).replace('${{ github.repository }}','fixture/repo')
policy=json.loads((root/'.github/rulesets/main-protection.json').read_text())
main={'id':1,'name':policy['name'],'target':'branch','enforcement':'active'}
state={'id':2,'name':'factory-reporting-state-protection','target':'branch','enforcement':'active'}
with tempfile.TemporaryDirectory() as tmp:
 path=pathlib.Path(tmp);(path/'.github/rulesets').mkdir(parents=True)
 (path/'.github/rulesets/main-protection.json').write_text(json.dumps(policy))
 gh=path/'gh';gh.write_text('#!/usr/bin/env python3\nimport json,os,sys\nf=json.loads(os.environ["RULESET_FIXTURE"])\nprint(json.dumps(f["list"] if sys.argv[-1].endswith("/rulesets") else f["details"][sys.argv[-1].rsplit("/",1)[-1]]))\n');gh.chmod(0o755)
 env=dict(os.environ);env['PATH']=str(path)+os.pathsep+env['PATH']
 cases=[('main first',[main,state],{'1':policy,'2':{'rules':[]}},True),
        ('state first',[state,main],{'1':policy,'2':{'rules':[]}},True),
        ('matching main missing',[state],{'2':{'rules':[]}},False),
        ('duplicate matching policy',[main,dict(main,id=3),state],{'1':policy,'3':policy,'2':{'rules':[]}},False),
        ('main missing contexts',[state,main],{'1':{'rules':[]},'2':policy},False)]
 for name,listing,details,success in cases:
  env['RULESET_FIXTURE']=json.dumps({'list':listing,'details':details})
  run=subprocess.run(['bash','-e','-c',script],cwd=path,env=env,capture_output=True,text=True)
  assert (run.returncode==0)==success,(name,run.stdout,run.stderr)
  print('PASS:',name)
 print('PASS: 5 actual workflow selection/drift cases')
PYTEST
