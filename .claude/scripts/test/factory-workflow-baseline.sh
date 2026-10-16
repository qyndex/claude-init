#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
actionlint
python3 - "$ROOT" <<'PYTEST'
from pathlib import Path
import json,os,re,subprocess,sys,tempfile
root=Path(sys.argv[1])
def body(filename,name):
 text=(root/'.github/workflows'/filename).read_text().split('- name: '+name,1)[1]
 match=re.search(r'        run: \|\n((?:          .*\n|\n)+)',text);assert match
 return '\n'.join(line[10:] for line in match.group(1).splitlines())
def run(script,base,env=None):
 return subprocess.run(['/bin/bash','-e','-o','pipefail','-c',script],cwd=base,env=env or {'PATH':os.environ['PATH']},capture_output=True,text=True)
# AC-5: execute the protected observation ingress exactly as shipped.
with tempfile.TemporaryDirectory() as directory:
 base=Path(directory);(base/'.claude').symlink_to(root/'.claude',target_is_directory=True)
 script=body('factory-merge.yml','Prepare protected policy observations')
 env={'PATH':os.environ['PATH'],'RUNNER_TEMP':directory,'GITHUB_REPOSITORY':'qyndex/claude-init','FACTORY_POLICY_OBSERVATIONS':''}
 result=run(script,base,env);assert result.returncode==0,result.stderr
 assert json.loads((base/'factory-policy-observations.json').read_text())=={'schema_version':1,'repository':'qyndex/claude-init','observations':[]}
 for raw in ('x'*262145,'{"schema_version":1,"schema_version":1}',json.dumps({'schema_version':1,'repository':'foreign/repo','observations':[]}),json.dumps({'schema_version':1,'repository':'qyndex/claude-init','observations':[],'secret':'DO_NOT_ECHO_SENTINEL'})):
  env['FACTORY_POLICY_OBSERVATIONS']=raw
  # Environment strings cannot exceed OS exec limits; invoke large fixture via shell export.
  if len(raw)>100000:
   (base/'oversized').write_text(raw);env['FACTORY_POLICY_OBSERVATIONS']='';invocation='export FACTORY_POLICY_OBSERVATIONS="$(cat oversized)"\n'+script
  else:invocation=script
  result=run(invocation,base,env);assert result.returncode!=0
  assert 'DO_NOT_ECHO_SENTINEL' not in result.stdout+result.stderr
 text=(root/'.github/workflows/factory-merge.yml').read_text()
 assert 'environment: factory-authority' in text and 'github.ref_name == github.event.repository.default_branch' in text
 assert 'permission-administration: read' in text and 'permission-administration: write' not in text
 assert 'FACTORY_POLICY_OBSERVATIONS: ${{ vars.FACTORY_POLICY_OBSERVATIONS }}' in text
 assert 'name: factory-policy-observation-' in text and 'path: factory-receipt/' in text
 assert 'path: ${{ runner.temp }}/factory-policy-audit/observation.json' in text
 print('AC-5: shipped protected ingress rejects foreign/duplicate/oversize/unknown JSON without raw echo; read-only App and separate audit retained')
print('AC-1: actual full actionlint including ShellCheck passes all shipped workflows without warning waivers')
with tempfile.TemporaryDirectory() as temporary:
 base=Path(temporary);(base/'.claude').mkdir();(base/'.github').mkdir();(base/'.mcp.json').write_text('{}')
 names=['space name.json','newline\nname.json',"quote'$(touch SHOULD_NOT_EXIST).json"]
 for name in names:(base/'.claude'/name).write_text('{"valid":true}')
 script=body('harness-validate.yml','Validate JSON files');assert run(script,base).returncode==0 and not (base/'SHOULD_NOT_EXIST').exists()
 invalid=base/'.claude'/'invalid.json';invalid.write_text('{');assert run(script,base).returncode!=0;invalid.unlink()
 (base/'.mcp.json').unlink();assert run(script,base).returncode!=0;(base/'.mcp.json').write_text('{}')
 tools=base/'tools';tools.mkdir();find=tools/'find';find.write_text('#!/bin/sh\nexit 42\n');find.chmod(0o755)
 assert run(script,base,{'PATH':str(tools)+':'+os.environ['PATH']}).returncode==42
 print('AC-2: shipped JSON validation accepts literal special filenames and rejects invalid JSON, missing roots and find exit 42')
 script=body('perf-budget.yml','Bundle size check');assert run(script,base).returncode!=0
 dist=base/'dist';dist.mkdir();assert run(script,base).returncode!=0
 asset=dist/"chunk'$(touch SHOULD_NOT_EXIST).js";asset.write_bytes(b'small real bundle');assert run(script,base).returncode==0 and not (base/'SHOULD_NOT_EXIST').exists()
 asset.write_bytes(os.urandom(250000));assert run(script,base).returncode!=0;asset.write_bytes(b'small bundle')
 find.unlink();compressor=tools/'gzip';compressor.write_text('#!/bin/sh\nexit 42\n');compressor.chmod(0o755)
 assert run(script,base,{'PATH':str(tools)+':'+os.environ['PATH']}).returncode!=0
 print('AC-3: shipped bundle gate handles literal filenames, rejects missing/empty assets and over-budget gzip bytes, and propagates compressor failure')
 gh=tools/'gh';log=base/'requests.jsonl'
 gh.write_text('#!/usr/bin/env python3\nimport json,os,sys\nfrom pathlib import Path\nargs=sys.argv[1:]\nwith Path(os.environ["REQUEST_LOG"]).open("a") as out:out.write(json.dumps(args)+"\\n")\nquery=next((arg for arg in args if arg.startswith("query=")), "")\nprint("" if query.startswith("query=\\nquery(") else ("NODE" if "/issues/" in " ".join(args) else ("ITEM" if "addProjectV2ItemById" in query else "{}")))\n')
 # Match the actual query content independently of indentation.
 source=gh.read_text().replace('query.startswith("query=\\nquery(")','"query(" in query');gh.write_text(source);gh.chmod(0o755)
 env={'PATH':str(tools)+':'+os.environ['PATH'],'REQUEST_LOG':str(log),'REPO':'fixture/repo','PROJECT_ID':'P1','ISSUE_NUM':'123','STATUS_FIELD_ID':'S1','TARGET_STATUS':'DONE'}
 result=run(body('issue-lifecycle.yml','Move project item'),base,env);assert result.returncode==0,result.stderr
 queries=[arg.removeprefix('query=') for line in log.read_text().splitlines() for arg in json.loads(line) if arg.startswith('query=')]
 assert len(queries)==3 and '$owner' in queries[0] and '$num' in queries[0] and '$project' in queries[1] and '$content' in queries[1] and '$opt' in queries[2]
 text=(root/'.github/workflows/stale-spec-check.yml').read_text();count=next(line.strip() for line in text.splitlines() if line.strip().startswith('completed='));tasks=base/'tasks';tasks.mkdir();ledger=tasks/'TASKS.md';ledger.write_text('')
 script='spec_base=012-example.md\n'+count+'\nprintf "%s" "$completed"';result=run(script,base);assert result.returncode==0 and result.stdout=='0'
 ledger.write_text('- [x] Spec: specs/active/012-example\n');assert run(script,base).stdout=='1'
 print('AC-4: shipped project shell preserves all literal GraphQL variables; actual stale count returns numeric zero or one without remote effects')
PYTEST
