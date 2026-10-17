#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""Stored batch cutoff owns confirmation, including actual lost-ack resume."""
from pathlib import Path
import hashlib,importlib.util,json,tempfile
spec=importlib.util.spec_from_file_location('confirm_digest',Path('.claude/scripts/factory-digest.py'));m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class Source:
 repo='org/repo'
 def request(self,*args,**kwargs):return [[]]
class Remote:
 def __init__(self):self.receipts={};self.sends=0
 def send(self,key,payload,destination):
  self.sends+=1;self.receipts[key]={'key':key,'payload_sha256':hashlib.sha256(payload.encode()).hexdigest(),'destination':destination,'message_id':'123.456'}
  raise RuntimeError('synthetic acknowledgement lost after remote send')
 def lookup(self,key):return {'receipt':self.receipts.get(key),'authoritative_absence':True}
with tempfile.TemporaryDirectory() as temp:
 for number,wrong_cutoff in enumerate(('2026-10-01T00:00:00+00:00','2026-10-16T00:00:00+00:00')):
  path=Path(temp)/str(number);digest=m.Digest(path,'org/repo','C1','2026-10-14T00:00:00Z');remote=Remote()
  batch=digest.prepare(Source(),'2026-10-15T00:00:00Z');original_payload=batch['payload'];original_cursor=digest.cursor()
  try:digest.deliver(batch['key'],remote)
  except RuntimeError:pass
  else:raise AssertionError('lost acknowledgement not observed')
  current=digest.batch(batch['key']);assert current['status']=='uncertain' and remote.sends==1
  receipt=remote.lookup(batch['key'])['receipt'];forged=dict(current,cutoff=wrong_cutoff)
  try:digest.confirm(forged,receipt)
  except ValueError as error:assert 'cutoff' in str(error)
  else:raise AssertionError('caller cutoff moved confirmed cursor')
  assert digest.cursor()==original_cursor and digest.batch(batch['key'])==current
  # Fresh instance consumes the exact visible receipt, never resending or rewriting bytes.
  resumed=m.Digest(path,'org/repo','C1','2026-10-14T00:00:00Z')
  assert resumed.deliver(batch['key'],remote)==receipt and remote.sends==1
  assert resumed.cursor()==batch['cutoff'] and resumed.batch(batch['key'])['payload']==original_payload
  confirmed=resumed.batch(batch['key'])
  try:resumed.confirm(dict(confirmed,cutoff=wrong_cutoff),receipt)
  except ValueError as error:assert 'cutoff' in str(error)
  else:raise AssertionError('confirmed row accepted caller cutoff mismatch')
  assert resumed.cursor()==batch['cutoff'] and resumed.confirm(confirmed,receipt)==receipt
print('stored cutoff binding rejects backward/future caller rows; actual uncertain fresh-instance receipt reconciliation and immutable payload PASS')
PY
