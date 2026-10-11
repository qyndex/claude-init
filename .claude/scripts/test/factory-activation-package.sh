#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PYTEST'
from pathlib import Path
import hashlib,json,os,re,subprocess,sys,tempfile
root=Path(sys.argv[1]);folder=root/'docs/activation/2026-10-11'
if (root/'.claude/install-manifest.json').is_file():
 print('SKIP: source pilot activation package is not distributed to adopters; no readiness proof claimed')
 raise SystemExit(0)
assert (folder/'manifest.json').is_file(), 'activation review package missing'
manifest=json.loads((folder/'manifest.json').read_text());policy=json.loads((folder/'policy.shadow.proposed.json').read_text())
assert manifest['proposal_only'] is True and manifest['live_authority_approved'] is False and manifest['model_requests']==0
assert policy['enabled'] is True and policy['merge_enabled'] is False
assert policy['app_id']==manifest['app_id'] and policy['repository']==manifest['repository']
def historical(path):return subprocess.check_output(['git','show',manifest['source_sha']+':'+path],cwd=root)
live_bytes=historical('factory/policy.json')
assert hashlib.sha256(live_bytes).hexdigest()==manifest['unchanged_live_policy_sha256']
assert json.loads(live_bytes)['enabled'] is False
for role in ['verification','review']:
 producer=policy['producers'][role]
 assert producer['workflow_id']==manifest['workflow_ids'][role]
 assert producer['event']=='pull_request_target'
 for path,digest in producer['trusted_files'].items():
  assert hashlib.sha256(historical(path)).hexdigest()==digest, 'stale runtime pin: '+path
assert policy['producers']['review']['workflow_id']!=policy['producers']['verification']['workflow_id']
assert policy['receipts']['trusted_revisions']=={} and manifest['receipt_revision_status']=='register actual approved coordinator source before first merge'
print('AC-1: source-bound complete runtime pins and shadow-only proposal; live policy unchanged')
approved=policy['specs']['048'];spec=folder/'spec-048.proposed.md';text=spec.read_text();assert subprocess.run(['git','cat-file','-e',manifest['source_sha']+':'+approved['path']],cwd=root,capture_output=True).returncode!=0, 'pilot was not approved at preparation source'
assert 'status: proposed' in text and approved['allowed_paths']==['docs/FACTORY-ADOPTER-QUICKSTART.md']
assert approved['sha256']==hashlib.sha256(spec.read_bytes()).hexdigest()
assert approved['task_ids']==['T-222'] and set(approved['acceptance_commands'])==set(approved['ac_ids'])=={'AC-1','AC-2','AC-3'}
assert approved['verification_image']==manifest['verification_image'] and re.fullmatch(r'python@sha256:[0-9a-f]{64}',approved['verification_image'])
assert manifest['pilot_approval_status']=='proposed; operator authority decision pending'
assert subprocess.run(['git','cat-file','-e',manifest['source_sha']+':docs/FACTORY-ADOPTER-QUICKSTART.md'],cwd=root,capture_output=True).returncode!=0, 'pilot delivery was absent at preparation source'
print('AC-2: complete proposed pilot scope and commands; no implementation or delivery claim')
checks=next(r for r in json.loads((folder/'ruleset.proposed.json').read_text())['rules'] if r['type']=='required_status_checks')['parameters']['required_status_checks']
expected=dict(policy['required_checks'],**{'factory-eligibility':policy['app_id']});pins={c['context']:c.get('integration_id') for c in checks}
assert all(pins.get(k)==v for k,v in expected.items())
assert manifest['review_state']==manifest['security_state']=='disabled_manually'
assert manifest['credential_metadata_only'] is True
with tempfile.TemporaryDirectory() as temp:
 base=Path(temp);script=base/'preflight.py';script.write_bytes(historical('.claude/scripts/factory-preflight.py'));config=base/'live.json';config.write_bytes(live_bytes)
 for name,selected,code in [('live',config,1),('shadow',folder/'policy.shadow.proposed.json',0)]:
  observed=json.loads((folder/('preflight.'+name+'.json')).read_text())
  result=subprocess.run([sys.executable,str(script),'--policy',str(selected)],env=dict(os.environ,FACTORY_APP_ID=str(policy['app_id']),FACTORY_KEY_PRESENT='true'),capture_output=True,text=True)
  assert result.returncode==code and json.loads(result.stdout)==observed
readme=(folder/'README.md').read_text();matrix=json.loads((folder/'shadow-cases.json').read_text())
assert len(matrix['cases'])>=8 and matrix['live_executed'] is False
assert {c['expected'] for c in matrix['cases']}=={'eligible-without-merge','blocked'}
for word in ['Tuesday','operator decision','shadow','receipt','twenty','rollback','paused','metadata']:
 assert word in readme,word
assert (folder/'ruleset.proposed.json').is_file()
print('AC-3/AC-4: complete proposal, reproducible metadata preflight, blocked live gates and ordered genuine-proof checklist')
PYTEST
bash "$ROOT/.claude/scripts/test/factory-coordinator.sh"
bash "$ROOT/.claude/scripts/test/factory-producers.sh"
