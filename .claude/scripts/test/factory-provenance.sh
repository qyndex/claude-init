#!/usr/bin/env bash
# AC-1/AC-4: immutable execution certificate, actual checkout, strict ZIP roots.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PY'
import copy,hashlib,importlib.util,io,json,os,pathlib,subprocess,sys,tempfile,zipfile
from unittest.mock import patch
root=pathlib.Path(sys.argv[1])
def load(name):
 spec=importlib.util.spec_from_file_location(name,root/'.claude/scripts'/('factory-'+name+'.py'));module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
m=load('provenance');c=load('coordinator')
repo='qyndex/claude-init';base='b'*40;head='a'*40
policy={'repository':repo,'base_branch':'main','producers':{'verification':{'trusted_files':{'source.py':hashlib.sha256(b'protected').hexdigest()}}}}
run={'id':123,'run_attempt':2,'head_sha':head,'repository':{'id':1,'full_name':repo},'head_repository':{'id':1,'full_name':repo}}
uri='https://github.com/'+repo+'/.github/workflows/factory-verification.yml@refs/heads/main'
cert={'issuer':'https://token.actions.githubusercontent.com','subjectAlternativeName':uri,'buildSignerURI':uri,'buildSignerDigest':base,'sourceRepositoryURI':'https://github.com/'+repo,'sourceRepositoryDigest':base,'sourceRepositoryRef':'refs/heads/main','buildTrigger':'pull_request_target','runnerEnvironment':'github-hosted','runInvocationURI':'https://github.com/'+repo+'/actions/runs/123/attempts/2'}
evidence=json.dumps({'head_sha':head,'base_sha':base}).encode();bundle=b'fixture injected at authenticated verifier seam, not a real signature'
result=[{'verificationResult':{'signature':{'certificate':cert},'verifiedTimestamps':[{'type':'fixture'}],'statement':{'subject':[{'name':'evidence.json','digest':{'sha256':hashlib.sha256(evidence).hexdigest()}}],'predicateType':'https://slsa.dev/provenance/v1','predicate':{'forged':'ignored'}}}}]
checks=0
def reject(fn):
 global checks
 try:fn()
 except (ValueError,KeyError,TypeError,subprocess.SubprocessError):checks+=1;return
 raise AssertionError('invalid execution/signature accepted')
def runner(command,**kwargs):
 assert command[:3]==['gh','attestation','verify']
 assert pathlib.Path(command[3]).read_bytes()==evidence
 assert pathlib.Path(command[command.index('--bundle')+1]).read_bytes()==bundle
 for flag,value in [('--repo',repo),('--source-digest',base),('--signer-digest',base),('--source-ref','refs/heads/main'),('--cert-identity',uri),('--cert-oidc-issuer','https://token.actions.githubusercontent.com')]:assert command[command.index(flag)+1]==value
 assert '--deny-self-hosted-runners' in command and kwargs['timeout']==60 and kwargs['limit']==2_000_000
 assert 'GH_TOKEN' not in kwargs['env'] and 'ACTIONS_ID_TOKEN_REQUEST_TOKEN' not in kwargs['env']
 return subprocess.CompletedProcess(command,0,json.dumps(result).encode(),b'')
m.verify(evidence,bundle,policy,'verification',run,base,runner=runner);checks+=1
for field in cert:
 previous=cert[field];cert[field]='forged';reject(lambda:m.verify(evidence,bundle,policy,'verification',run,base,runner=runner));cert[field]=previous
previous=copy.deepcopy(result[0]['verificationResult'])
for mutate in [lambda v:v.pop('signature'),lambda v:v.update(verifiedTimestamps=[]),lambda v:v['statement']['subject'][0].update(digest={'sha256':'0'*64}),lambda v:v['statement'].update(predicateType='other')]:
 mutate(result[0]['verificationResult']);reject(lambda:m.verify(evidence,bundle,policy,'verification',run,base,runner=runner));result[0]['verificationResult']=copy.deepcopy(previous)
# Correct user-controllable predicate claims cannot rescue an invalid certificate.
result[0]['verificationResult']['statement']['predicate']=dict(cert);result[0]['verificationResult']['signature']['certificate']['sourceRepositoryDigest']=head
reject(lambda:m.verify(evidence,bundle,policy,'verification',run,base,runner=runner));result[0]['verificationResult']=copy.deepcopy(previous)
reject(lambda:m.verify(evidence,b'x'*1_000_001,policy,'verification',run,base,runner=runner))
reject(lambda:m.verify(evidence,bundle,policy,'verification',run,base,runner=lambda *args,**kwargs:subprocess.CompletedProcess(args,1,b'[]',b'bad signature')))
with tempfile.TemporaryDirectory() as folder:
 p=pathlib.Path(folder);(p/'source.py').write_bytes(b'protected')
 helper='.claude/scripts/factory-policy-observation.py'
 material=p/helper;material.parent.mkdir(parents=True);material.write_bytes(b'protected-helper')
 policy['producers']['verification']['trusted_files'][helper]=hashlib.sha256(b'protected-helper').hexdigest()
 for args in [['init','-q'],['config','user.name','Provenance fixture'],['config','user.email','fixture@example.invalid'],['add','.'],['commit','-qm','test: protected source fixture']]:subprocess.run(['git','-C',str(p),*args],check=True,capture_output=True)
 execution=subprocess.check_output(['git','-C',str(p),'rev-parse','HEAD'],text=True).strip()
 event=p/'event.json';event.write_text(json.dumps({'number':42,'repository':{'full_name':repo}}))
 env={'GITHUB_ACTIONS':'true','GITHUB_EVENT_NAME':'pull_request_target','GITHUB_REPOSITORY':repo,'GITHUB_REF':'refs/heads/main','GITHUB_SHA':execution,'GITHUB_WORKFLOW_SHA':execution,'GITHUB_WORKFLOW_REF':uri.removeprefix('https://github.com/'),'GITHUB_RUN_ID':'123','GITHUB_RUN_ATTEMPT':'2','GITHUB_EVENT_PATH':str(event)}
 assert m.execution_base(policy,'verification',run,42,environ=env,root=p)==execution;checks+=1
 for key in env:
  altered={**env,key:'forged'}
  reject(lambda:m.execution_base(policy,'verification',run,42,environ=altered,root=p))
 (p/'source.py').write_bytes(b'tampered');reject(lambda:m.execution_base(policy,'verification',run,42,environ=env,root=p));(p/'source.py').write_bytes(b'protected')
 material.write_bytes(b'forged-helper');reject(lambda:m.execution_base(policy,'verification',run,42,environ=env,root=p));material.write_bytes(b'protected-helper')
 subprocess.run(['git','-C',str(p),'commit','--allow-empty','-qm','test: changed protected HEAD'],check=True,capture_output=True)
 reject(lambda:m.execution_base(policy,'verification',run,42,environ=env,root=p))
# Actual bounded ZIP extraction requires metadata and signed evidence root; no unsigned target fallback.
def archive(signed=True,extra=None):
 buffer=io.BytesIO()
 with zipfile.ZipFile(buffer,'w') as z:
  z.writestr('evidence.json',evidence)
  if signed:z.writestr('provenance.sigstore.json',bundle)
  if extra:z.writestr(extra,b'forged')
 return buffer.getvalue()
metadata={'id':123,'head_sha':head,'repository_id':1,'head_repository_id':1}
class API(c.GitHub):
 def __init__(self,blob):super().__init__(repo);self.blob=blob;self.metadata=copy.deepcopy(metadata)
 def request(self,path,**kwargs):
  if path.endswith('/zip'):return self.blob
  return [{'artifacts':[{'id':2,'name':'proof','expired':False,'size_in_bytes':len(self.blob),'digest':'sha256:'+hashlib.sha256(self.blob).hexdigest(),'workflow_run':self.metadata}]}]
with patch.object(c.provenance,'verify') as verifier:
 api=API(archive());document,blobs=api.artifact(run,'proof',policy=policy,role='verification',base=base);assert document['base_sha']==base;verifier.assert_called_once();checks+=1
 for bad in [API(archive(False)),API(archive(extra='../escape'))]:reject(lambda:bad.artifact(run,'proof',policy=policy,role='verification',base=base))
 for key in metadata:
  bad=API(archive());bad.metadata[key]='forged';reject(lambda:bad.artifact(run,'proof',policy=policy,role='verification',base=base))
 bad=API(archive());bad.metadata={};reject(lambda:bad.artifact(run,'proof',policy=policy,role='verification',base=base))
 for bad_base in [head,'c'*40]:
  # Signature verifier receives caller's current base, never the artifact's claimed base.
  verifier.reset_mock();api.artifact(run,'proof',policy=policy,role='verification',base=bad_base);assert verifier.call_args.args[-1]==bad_base;checks+=1
for role in ['verification','review']:
 workflow=(root/'.github/workflows'/f'factory-{role}.yml').read_text()
 assert 'id-token: write' in workflow and 'attestations: write' in workflow
 assert 'actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6' in workflow
 assert "if: steps.proof.outcome == 'success'" in workflow and 'producer-output/evidence.json' in workflow
 assert '[ "$SIGNATURE" = success ]' in workflow and '[ "$SIGNATURE_BUNDLE" = success ]' in workflow
 assert '.claude/scripts/factory-provenance.py' in c.runtime_paths(role)
 assert len(c.runtime_paths(role))==9 and '.claude/scripts/factory-policy-observation.py' in c.runtime_paths(role)
print('provenance: PASS; assertions='+str(checks)+'; injected verified-certificate positive fixtures; nonzero verifier rejection; no live signing/hosted verdict')
PY
