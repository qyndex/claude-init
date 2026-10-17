from pathlib import Path
import json,hashlib,importlib.util
root=Path.cwd();old=json.loads((root/'factory/receipt-trust.json').read_text());policy=json.loads((root/'factory/policy.json').read_text());base=json.loads(__import__('subprocess').check_output(['git','show','94e40be14af35b11bbd81d355a723141c4383299:factory/policy.json']))
assert policy['merge_enabled'] is True, 'reviewed cutover must enable merge in source policy'
assert {**policy,'merge_enabled':False}==base, 'unrelated policy change'
s=importlib.util.spec_from_file_location('receipts',root/'.claude/scripts/factory-receipts.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
trust=m.load_receipt_trust(root/'factory/receipt-trust.json','qyndex/claude-init',mode='profile');digest=m.coordinator.policy_hash(policy)
matched=[p for p in trust['profiles'] if p['policy_sha256']==digest and p['status']=='active'];assert len(matched)==1,'exact new policy profile missing/ambiguous'
original=json.loads(__import__('subprocess').check_output(['git','show','94e40be14af35b11bbd81d355a723141c4383299:factory/receipt-trust.json']))
assert trust['profiles'][:-1]==original['profiles'] and trust['legacy_revisions']==original['legacy_revisions'],'historical profile changed'
assert matched[0]['runtime']==original['profiles'][0]['runtime'],'runtime unexpectedly changed'
for name,value in matched[0]['runtime'].items():assert hashlib.sha256((root/name).read_bytes()).hexdigest()==value,name
print('PASS exact merge-only policy delta; old profile preserved; new canonical policy and seven immutable runtime pins validated')
