#!/usr/bin/env bash
set -euo pipefail
ROOT="${DIGEST_COVERAGE_TEST_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
python3 - "$ROOT" <<'PY'
from pathlib import Path
import copy,hashlib,importlib.util,json,sys,tempfile
spec=importlib.util.spec_from_file_location('digest',Path(sys.argv[1])/'.claude/scripts/factory-digest.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
def reject(fn):
    try:fn()
    except (ValueError,RuntimeError):return
    raise AssertionError('contradictory coverage accepted')
class API:
    repo='org/repo'
    def __init__(self):self.prs=[self.pr(1,'2026-10-02T00:00:00Z')]
    def pr(self,n,at):return {'number':n,'title':f'Change {n}','html_url':f'https://github.com/org/repo/pull/{n}','merged_at':at,'merge_commit_sha':'b'*40,'head':{'sha':'c'*40},'base':{'ref':'main','repo':{'full_name':self.repo}}}
    def request(self,path,**opts):return [self.prs[:1],self.prs[1:]]
class Remote:
    def __init__(self):self.messages={};self.drop=False;self.sends=0
    def send(self,key,payload,destination):
        self.sends+=1
        receipt={'key':key,'payload_sha256':hashlib.sha256(payload.encode()).hexdigest(),'destination':destination,'message_id':str(self.sends)}
        self.messages[key]=receipt
        if self.drop:raise RuntimeError('response lost')
        return receipt
    def lookup(self,key):return {'receipt':self.messages.get(key),'authoritative_absence':False}
with tempfile.TemporaryDirectory() as tmp:
    db=Path(tmp)/'db';d=m.Digest(db,'org/repo','C1','2026-10-01T00:00:00Z');api=API();remote=Remote()
    first=d.prepare(api,'2026-10-03T00:00:00Z');d.deliver(first['key'],remote)
    api.prs += [api.pr(2,'2026-10-02T00:00:00Z'),api.pr(3,'2026-10-03T00:00:00Z'),api.pr(4,'2026-09-30T00:00:00Z')]
    second=d.prepare(api,'2026-10-04T00:00:00Z');merges=json.loads(second['payload'])['merges']
    assert [p['pr'] for p in merges]==[2,3], 'late merges lost after cursor advancement'
    assert all(p['late_discovered'] is True for p in merges)
    slack_spec=importlib.util.spec_from_file_location('slack',Path(sys.argv[1])/'.claude/scripts/factory-slack-digest.py')
    slack=importlib.util.module_from_spec(slack_spec);slack_spec.loader.exec_module(slack)
    assert slack.render(second['payload']).count('[late discovery]')==2
    remote.drop=True;reject(lambda:d.deliver(second['key'],remote));assert d.cursor()==first['cutoff']
    assert d.prepare(api,'2026-10-05T00:00:00Z')['key']==second['key']
    remote.drop=False;d.deliver(second['key'],remote);assert remote.sends==2
    # Existing report databases reconstruct the immutable origin from earliest bytes.
    with d.transaction() as conn:conn.execute('DROP TABLE digest_origins')
    migrated=m.Digest(db,'org/repo','C1','2026-09-01T00:00:00Z')
    third=migrated.prepare(api,'2026-10-05T00:00:00Z');assert json.loads(third['payload'])['merges']==[]
    migrated.deliver(third['key'],remote)
    api.prs[0]['merge_commit_sha']='e'*40
    before=migrated.cursor();reject(lambda:migrated.prepare(api,'2026-10-06T00:00:00Z'));assert migrated.cursor()==before
    api.prs[0]['merge_commit_sha']='b'*40
    with migrated.transaction() as conn:conn.execute("UPDATE digest_batches SET payload='invalid json' WHERE key=?",(third['key'],))
    reject(lambda:migrated.prepare(api,'2026-10-06T00:00:00Z'));assert migrated.cursor()==before
print('factory-digest-coverage: late/equal-time discovery, no repeats, uncertain recovery, origin migration and contradictory history passed')
PY
