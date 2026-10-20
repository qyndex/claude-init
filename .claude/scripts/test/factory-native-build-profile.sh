#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PY'
import copy,hashlib,importlib.util,json,os,subprocess,sys,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
root=Path(sys.argv[1]);sys.dont_write_bytecode=True
spec=importlib.util.spec_from_file_location('producer',root/'.claude/scripts/factory-producer.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
IMAGE='example/verifier@sha256:'+'c'*64
class ProfileContract(unittest.TestCase):
 def command(self,profile=None):
  args=(IMAGE,Path('/candidate-root'),'owned-container',['node','test.mjs'])
  return m.sandbox_command(*args) if profile is None else m.sandbox_command(*args,profile=profile)
 def test_existing_default_is_explicitly_strict_and_environment_cannot_override(self):
  with patch.dict(os.environ,{'FACTORY_SANDBOX_PROFILE':'native-build-v1','DOCKER_OPTS':'--privileged --network host'}):command=self.command()
  self.assertEqual(command[command.index('--tmpfs')+1],'/tmp:rw,nosuid,nodev,noexec,size=1g')
  self.assertNotIn('--privileged',command);self.assertNotIn('host',command)
 def test_only_native_profile_changes_scratch_exec_and_nothing_else(self):
  strict=self.command('strict-interpreted-v1');native=self.command('native-build-v1');index=strict.index('--tmpfs')+1
  self.assertEqual(native[index],'/tmp:rw,nosuid,nodev,exec,size=1g')
  native[index]=strict[index];self.assertEqual(native,strict)
  for flag,value in {'--network':'none','--cap-drop':'ALL','--security-opt':'no-new-privileges','--pids-limit':'256','--memory':'2g','--cpus':'2','--user':'65532:65532'}.items():self.assertEqual(strict[strict.index(flag)+1],value)
  self.assertIn('--read-only',strict);self.assertEqual(strict[strict.index('--mount')+1],'type=bind,src=/candidate-root,dst=/candidate,readonly')
 def test_unknown_and_arbitrary_option_profiles_reject_before_runner(self):
  for profile in ['',None,False,{},[],{'tmpfs':'exec'},'native-build-v2','native-build-v1 --privileged','--network=host']:
   with self.subTest(profile=profile),tempfile.TemporaryDirectory() as folder:
    out=Path(folder);(out/'artifacts').mkdir();calls=[]
    approved={'ac_ids':['AC-1'],'acceptance_commands':{'AC-1':['true']},'verification_image':IMAGE,'sandbox_profile':profile}
    def runner(*args,**kwargs):calls.append(args);return subprocess.CompletedProcess(args,0)
    with self.assertRaises(ValueError):m.verify(approved,out,out,{'head_sha':'a'*40},'fixture',runner)
    self.assertEqual(calls,[])
 def test_registered_profile_is_used_and_retained_in_hashed_observation(self):
  for profile in ('strict-interpreted-v1','native-build-v1'):
   with self.subTest(profile=profile),tempfile.TemporaryDirectory() as folder:
    out=Path(folder);(out/'artifacts').mkdir();approved={'ac_ids':['AC-1'],'acceptance_commands':{'AC-1':['node','test.mjs']},'verification_image':IMAGE,'sandbox_profile':profile}
    def runner(command,**kwargs):
     self.assertIn('noexec' if profile.startswith('strict') else ',exec,',command[command.index('--tmpfs')+1]);kwargs['stdout'].write(b'real fixture output');return subprocess.CompletedProcess(command,0)
    result=m.verify(approved,out,out,{'head_sha':'a'*40},'fixture',runner);digest=result['acceptance'][0]['artifact_sha256'];raw=(out/'artifacts'/digest).read_bytes();self.assertEqual(hashlib.sha256(raw).hexdigest(),digest);self.assertEqual(json.loads(raw)['sandbox_profile'],profile)
 def test_verify_absent_profile_preserves_strict_default(self):
  with tempfile.TemporaryDirectory() as folder:
   out=Path(folder);(out/'artifacts').mkdir();approved={'ac_ids':['AC-1'],'acceptance_commands':{'AC-1':['node','test.mjs']},'verification_image':IMAGE};calls=[]
   def runner(command,**kwargs):
    calls.append(command);self.assertIn(',noexec,',command[command.index('--tmpfs')+1]);kwargs['stdout'].write(b'default fixture output');return subprocess.CompletedProcess(command,0)
   with patch.dict(os.environ,{'FACTORY_SANDBOX_PROFILE':'native-build-v1'}):result=m.verify(approved,out,out,{'head_sha':'a'*40},'fixture',runner)
   self.assertEqual(len(calls),1);raw=(out/'artifacts'/result['acceptance'][0]['artifact_sha256']).read_bytes();self.assertEqual(json.loads(raw)['sandbox_profile'],'strict-interpreted-v1')
 def test_changed_profile_invalidates_existing_policy_binding(self):
  strict={'specs':{'010':{'sandbox_profile':'strict-interpreted-v1'}}};native=copy.deepcopy(strict);native['specs']['010']['sandbox_profile']='native-build-v1'
  context={'schema_version':1,'repository':'org/repo','pull_request':1,'head_sha':'a'*40,'base_sha':'b'*40,'spec_sha256':'c'*64,'policy_sha256':m.coordinator.policy_hash(native),'ac_ids':['AC-1'],'implementer':'builder','allowed_verifiers':['verifier'],'allowed_reviewers':['reviewer'],'required_checks':{'tests':1},'window_start':'2026-10-20T00:00:00Z','window_end':'2026-10-20T01:00:00Z'}
  evidence={key:context[key] for key in m.coordinator.contract.BINDING};evidence.update(generated_at='2026-10-20T00:30:00Z',acceptance=[],checks=[],verification={},review={});evidence['policy_sha256']=m.coordinator.policy_hash(strict)
  with self.assertRaisesRegex(ValueError,'policy_sha256: candidate binding mismatch'):m.coordinator.contract.validate(context,evidence)
 def test_preflight_reports_unknown_protected_registration(self):
  with tempfile.TemporaryDirectory() as folder:
   policy=json.loads((root/'factory/policy.json').read_text());policy['specs']['010']={'sandbox_profile':'--privileged'};path=Path(folder)/'policy.json';path.write_text(json.dumps(policy));result=subprocess.run([sys.executable,str(root/'.claude/scripts/factory-preflight.py'),'--policy',str(path)],capture_output=True,text=True)
   self.assertNotEqual(result.returncode,0);self.assertIn('spec 010 supported sandbox profile',json.loads(result.stdout)['missing'])
unittest.main(argv=[sys.argv[0]],verbosity=2)
PY
