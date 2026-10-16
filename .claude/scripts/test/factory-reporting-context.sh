#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-6/AC-8: fixed nonsecret checkout selection cannot redirect protected inputs."""
import importlib.util,json,tempfile,copy,os
from pathlib import Path
s=importlib.util.spec_from_file_location('t',Path('.claude/scripts/factory-reporting-transport.py'));t=importlib.util.module_from_spec(s);s.loader.exec_module(t)
with tempfile.TemporaryDirectory() as directory:
 root=Path(directory);fixed=root/'factory';fixed.mkdir()
 policy=json.loads(Path('factory/policy.json').read_text());repo=policy['repository']
 values={'policy.json':policy,'receipt-store.json':{'repository':repo,'visibility':'public'},'receipt-trust.json':{'schema_version':1,'repository':repo,'profiles':[],'legacy_revisions':{}},'receipt-archive-bootstrap.json':{'schema_version':2,'repository':repo,'branch':'state','writer_app_id':7},'receipt-policy-observations.json':{'schema_version':1,'repository':repo}}
 for name,value in values.items():(fixed/name).write_text(json.dumps(value))
 config={'repository':repo,'state_repository':repo,'state_branch':'state','enabled':True}
 os.environ['FACTORY_REPORTING_APP_ID']='7'
 before=copy.deepcopy(config)
 result=t.attach_reporting_context(config,checkout=root)
 assert config==before and result['receipt_mode']=='durable'
 assert result['receipt_archive']=={'approval_path':str((fixed/'receipt-archive-bootstrap.json').resolve()),'trust_path':str((fixed/'receipt-trust.json').resolve()),'store':values['receipt-store.json'],'trust_mode':'profile'}
 assert result['state_view']=={'mode':'archive','approval_path':result['receipt_archive']['approval_path']}
 def reject(fn):
  try:fn()
  except ValueError:return
  raise AssertionError('unsafe fixed checkout context accepted')
 reject(lambda:t.attach_reporting_context(dict(config,receipt_archive={'approval_path':'/tmp/foreign'}),checkout=root))
 reject(lambda:t.attach_reporting_context(dict(config,state_branch='foreign'),checkout=root))
 os.environ['FACTORY_REPORTING_APP_ID']='8';reject(lambda:t.attach_reporting_context(config,checkout=root));os.environ['FACTORY_REPORTING_APP_ID']='7'
 for name,value in values.items():
  path=fixed/name;raw=path.read_bytes();path.unlink()
  reject(lambda:t.attach_reporting_context(config,checkout=root))
  path.symlink_to(fixed/'policy.json');reject(lambda:t.attach_reporting_context(config,checkout=root));path.unlink();path.write_bytes(raw)
 store=fixed/'receipt-store.json';store.write_text('{"repository":"foreign/repo","visibility":"public"}');reject(lambda:t.attach_reporting_context(config,checkout=root));store.write_text(json.dumps(values['receipt-store.json']))
 store.write_text('{"repository":"'+repo+'","visibility":"public","visibility":"private"}');reject(lambda:t.attach_reporting_context(config,checkout=root))
 store.write_bytes(b' '*1048577);reject(lambda:t.attach_reporting_context(config,checkout=root))
 print('fixed protected checkout context selection, missing/symlink/foreign/duplicate/oversize rejection PASS')
PY
