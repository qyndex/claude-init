#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-1/AC-5: missing helper runtime must block metadata readiness."""
import copy,hashlib,importlib.util,json,os,subprocess,tempfile
from pathlib import Path
policy=json.loads(Path('factory/policy.json').read_text());helper='.claude/scripts/factory-policy-observation.py'
with tempfile.TemporaryDirectory() as temp:
 path=Path(temp)/'policy.json';env=dict(os.environ,FACTORY_APP_ID=str(policy['app_id']),FACTORY_KEY_PRESENT='true')
 def run(doc):
  path.write_text(json.dumps(doc));return subprocess.run(['python3','.claude/scripts/factory-preflight.py','--policy',str(path)],env=env,capture_output=True,text=True)
 for role in ('verification','review'):
  bad=copy.deepcopy(policy);bad['producers'][role]['trusted_files'].pop(helper,None)
  result=run(bad);assert result.returncode==1 and f'{role} complete transitive runtime hashes' in result.stdout
 result=run(policy);assert result.returncode==0,result.stdout
 for role in ('verification','review'):
  pins=policy['producers'][role]['trusted_files'];assert len(pins)==8 and helper in pins
  for name,digest in pins.items():assert hashlib.sha256(Path(name).read_bytes()).hexdigest()==digest,name
 before=json.loads(subprocess.check_output(['git','show','6606a1b3392bc8f867b46e5b1e81bbf86be34d6e:factory/policy.json']))
 after=copy.deepcopy(policy)
 for role in ('verification','review'):
  before['producers'][role].pop('trusted_files');after['producers'][role].pop('trusted_files')
 assert before==after and after['merge_enabled'] is False and after['receipts']['trusted_revisions']=={}
 s=importlib.util.spec_from_file_location('receipts','.claude/scripts/factory-receipts.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
 assert len(m.RUNTIME_PATHS)==7 and helper in m.RUNTIME_PATHS
print('preflight: PASS; missing helper in either role blocks, current complete8-file pins match bytes; unrelated policy unchanged; emitter7 paths; fixture metadata only, no credential authentication')
PY
