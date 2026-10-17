#!/usr/bin/env bash
# Spec029 AC-9: typed historical proof, never delivery/current-readiness authority.
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
from pathlib import Path
import copy,hashlib,importlib.util,json,subprocess
from datetime import datetime,timezone
path=Path('.claude/scripts/factory-operational-proof.py')
assert path.is_file(), 'distinct authenticated historical operational-proof contract missing'
s=importlib.util.spec_from_file_location('operational',path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
repo={'name':'org/repo','id':101,'private':False};old='a'*40;new='b'*40
original={'source_sha':old,'workflow_path':'.github/workflows/factory-reporting-queue.yml','workflow_id':10,
 'runtime':{'.github/workflows/factory-reporting-queue.yml':'1'*64,'.claude/scripts/factory-reporting-queue-evidence.py':'2'*64}}
producer={'source_sha':new,'workflow_path':'.github/workflows/factory-operational-proof.yml','workflow_id':11,
 'runtime':{'.github/workflows/factory-operational-proof.yml':'3'*64,'.claude/scripts/factory-operational-proof.py':'4'*64,'.claude/scripts/factory-bounded-process.py':'5'*64}}
profile={'schema_version':1,'profile_id':'historical-test','profile_sha256':'9'*64,'status':'active','repository':repo,'branch':'main','original':original,'producer':producer}
runs=[{'role':role,'run_id':20+i,'attempt':1,'job_id':30+i,'started_at':f'2026-10-16T01:0{i}:00Z','ended_at':f'2026-10-16T01:0{i}:10Z','log_sha256':str(i+6)*64,'notifications':counts}
      for i,(role,counts) in enumerate((('drill',[1,0]),('recovery',[1]),('repeat',[0])))]
state={'branch':'state','head_sha':'c'*40,'tree_sha':'d'*40,'journal_path':'reports/'+'e'*64+'.json','journal_sha256':'f'*64,'lineage_sha256':'0'*64,'drill_key':'1'*64,'recovery_key':'2'*64,'publication_count':5}
record={'schema_version':1,'type':'historical-queue-completion','purpose':'historical-operational-acceptance','profile_id':'historical-test','profile_sha256':'9'*64,'repository':repo,
 'original':dict(original,runs=runs,state=state),'verification':dict(producer,run_id=40,attempt=2,started_at='2026-10-17T02:00:00Z',verified_at='2026-10-17T02:00:00.100000Z')}
now=datetime(2026,10,17,3,tzinfo=timezone.utc)
native={'id':40,'run_attempt':2,'workflow_id':11,'path':producer['workflow_path'],'head_sha':new,'head_branch':'main','event':'workflow_dispatch','status':'completed','conclusion':'success',
 'repository':{'id':101,'full_name':'org/repo'},'head_repository':{'id':101,'full_name':'org/repo'},'run_started_at':'2026-10-17T02:00:00Z','updated_at':'2026-10-17T02:00:01Z'}
uri='https://github.com/org/repo/'+producer['workflow_path']+'@refs/heads/main'
cert={'issuer':'https://token.actions.githubusercontent.com','subjectAlternativeName':uri,'buildSignerURI':uri,'buildSignerDigest':new,'sourceRepositoryURI':'https://github.com/org/repo','sourceRepositoryIdentifier':'101','sourceRepositoryDigest':new,'sourceRepositoryRef':'refs/heads/main','buildTrigger':'workflow_dispatch','runnerEnvironment':'github-hosted','runInvocationURI':'https://github.com/org/repo/actions/runs/40/attempts/2'}
raw=m.canonical(record)
verified=[{'verificationResult':{'signature':{'certificate':cert},'verifiedTimestamps':[{'type':'Tlog','uri':'https://rekor.example.test','timestamp':'2026-10-17T02:00:01.900000001Z'}],
 'statement':{'_type':'https://in-toto.io/Statement/v1','predicateType':'https://slsa.dev/provenance/v1','subject':[{'name':'operational-proof.json','digest':{'sha256':hashlib.sha256(raw).hexdigest()}}], 'predicate':{'current_readiness':True}}}}]
calls=[]
def runner(command,**kwargs):
 calls.append(command)
 assert command[:3]==['gh','attestation','verify'] and '--deny-self-hosted-runners' in command
 for flag,value in (('--repo','org/repo'),('--cert-identity',uri),('--source-digest',new),('--signer-digest',new),('--source-ref','refs/heads/main')):assert command[command.index(flag)+1]==value
 assert kwargs['timeout']==60 and kwargs['limit']==2000000
 assert not any(key in kwargs['env'] for key in ('GH_TOKEN','GITHUB_TOKEN','ACTIONS_ID_TOKEN_REQUEST_TOKEN'))
 return subprocess.CompletedProcess(command,0,json.dumps(verified).encode(),b'')
assert m.validate_record(raw,profile,now=now)==record
assert m.verify(raw,b'fixture-bundle',profile,native,runner=runner,now=now)==record
assert len(calls)==1
count=0
def reject(fn):
 global count
 try:fn()
 except ValueError:count+=1;return
 raise AssertionError('invalid historical operational proof accepted')
for key,value in [('type','delivery'),('purpose','current-readiness'),('schema_version',True),('profile_id','foreign')]:
 bad=copy.deepcopy(record);bad[key]=value;reject(lambda:m.validate_record(m.canonical(bad),profile,now=now))
for status in ('revoked','withdrawn','inactive','unknown'):
 bad=copy.deepcopy(profile);bad['status']=status;reject(lambda:m.validate_record(raw,bad,now=now))
for area,field,value in [('repository','id',True),('repository','name','foreign/repo'),('original','source_sha',new),('verification','source_sha',old),('verification','attempt',False),('verification','verified_at','2026-10-18T00:00:00Z')]:
 bad=copy.deepcopy(record);bad[area][field]=value;reject(lambda:m.validate_record(m.canonical(bad),profile,now=now))
for field in ('run_id','attempt','job_id'):
 bad=copy.deepcopy(record);bad['original']['runs'][0][field]=True;reject(lambda:m.validate_record(m.canonical(bad),profile,now=now))
for field,value in [('journal_path','../private'),('journal_sha256','z'*64),('publication_count',25)]:
 bad=copy.deepcopy(record);bad['original']['state'][field]=value;reject(lambda:m.validate_record(m.canonical(bad),profile,now=now))
for encoded in (raw+b' ',b'{"schema_version":1,"schema_version":1}',b'{"value":NaN}',b'x'*262145,b'[]',raw[:-1]):reject(lambda:m.validate_record(encoded,profile,now=now))
bad=copy.deepcopy(record);bad['merge_authorized']=True;reject(lambda:m.validate_record(m.canonical(bad),profile,now=now))
for field in cert:
 saved=cert[field];cert[field]='forged';reject(lambda:m.verify(raw,b'fixture',profile,native,runner=runner,now=now));cert[field]=saved
saved_id=cert.pop('sourceRepositoryIdentifier')
reject(lambda:m.verify(raw,b'fixture',profile,native,runner=runner,now=now))
cert['sourceRepositoryIdentifier']=saved_id
for field,value in [('workflow_id',12),('id',False),('run_attempt',3),('event','pull_request_target'),('head_sha',old),('conclusion','failure')]:
 bad=copy.deepcopy(native);bad[field]=value;reject(lambda:m.verify(raw,b'fixture',profile,bad,runner=runner,now=now))
timestamps=verified[0]['verificationResult']['verifiedTimestamps'];saved=copy.deepcopy(timestamps)
for value in ([],[{'type':'Tlog','uri':'http://unsafe','timestamp':'2026-10-17T02:00:01Z'}],[{'type':'Tlog','uri':'https://rekor.example.test','timestamp':'2026-10-17T02:00:02Z'}],[{'type':'Tlog','uri':'https://rekor.example.test','timestamp':'2026-10-17T02:00:00.099999999Z'}]):
 verified[0]['verificationResult']['verifiedTimestamps']=value;reject(lambda:m.verify(raw,b'fixture',profile,native,runner=runner,now=now))
verified[0]['verificationResult']['verifiedTimestamps']=saved
verified[0]['verificationResult']['verifiedTimestamps'][0]['timestamp']='2026-10-17T03:00:01.900000001+01:00'
assert m.verify(raw,b'fixture',profile,native,runner=runner,now=now)==record
verified[0]['verificationResult']['statement']['subject'][0]['digest']['sha256']='0'*64
reject(lambda:m.verify(raw,b'fixture',profile,native,runner=runner,now=now))
reject(lambda:m.verify(raw,b'fixture',profile,native,runner=lambda *a,**k:subprocess.CompletedProcess(a,1,b'',b'bad signature'),now=now))
reject(lambda:m.verify(raw,b'x'*1000001,profile,native,runner=runner,now=now))
# Focused strictness/precision controls; synthetic verifier seam remains explicit.
reject(lambda:m.stamp('2026-10-17T02:00:00+00:60'))
for name in ('. /repo'.replace(' ',''),'org/..','a'*202+'/repo'):
 bad=copy.deepcopy(profile);bad['repository']['name']=name
 reject(lambda:m.validate_record(raw,bad,now=now))
same_second=copy.deepcopy(record);same_second['verification']['verified_at']='2026-10-17T02:00:01.100000001Z'
same_raw=m.canonical(same_second)
verified[0]['verificationResult']['statement']['subject'][0]['digest']['sha256']=hashlib.sha256(same_raw).hexdigest()
assert m.verify(same_raw,b'fixture',profile,native,runner=runner,now=now)==same_second
same_second['verification']['verified_at']='2026-10-17T02:00:02Z'
reject(lambda:m.verify(m.canonical(same_second),b'fixture',profile,native,runner=runner,now=now))
print('operational proof PASS; negative assertions='+str(count)+'; synthetic gh-verified certificate fixture seam only; no actual Sigstore/native/live proof')
PY
