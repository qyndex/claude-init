#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
import copy, importlib.util, json, os, subprocess, sys, tempfile, unittest
from pathlib import Path
script=Path('.claude/scripts/retain-claude-review.py').resolve()
spec=importlib.util.spec_from_file_location('review',script);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
binding={'repository':'example/project','pr':12,'head':'a'*40,'role':'code'}
review={**binding,'summary':'No actionable findings after rereading changed code.','findings':[],'suppressed':0}
result={'type':'result','subtype':'success','is_error':False,'num_turns':3,'permission_denials':[],'modelUsage':{m.MODEL:{'inputTokens':100,'outputTokens':50}},'structured_output':review}
class Evidence(unittest.TestCase):
 def rejects(self, rows):
  with self.assertRaises(ValueError):m.validate(rows,binding)
 def test_zero_finding_review_is_retained(self):
  self.assertEqual(m.validate([result],binding),review)
 def test_green_action_without_structured_review_is_not_review(self):
  row=copy.deepcopy(result);del row['structured_output'];self.rejects([row])
 def test_missing_partial_duplicate_or_following_result_rejects(self):
  for rows in [[],[{'type':'assistant'}],[result,result],[result,{'type':'assistant'}]]:self.rejects(rows)
 def test_failed_or_exhausted_execution_rejects(self):
  for key,value in [('is_error',True),('subtype','error_max_turns'),('num_turns',41),('num_turns',True)]:
   row=copy.deepcopy(result);row[key]=value;self.rejects([row])
 def test_denials_missing_and_wrong_model_reject(self):
  for field,value in [('permission_denials',[{'tool':'Bash'}]),('permission_denials',None),('modelUsage',{}),('modelUsage',{m.MODEL:{},'other':{}})]:
   row=copy.deepcopy(result);row[field]=value;self.rejects([row])
 def test_each_binding_is_required_and_exact(self):
  for key,value in [('repository','other/project'),('pr',True),('head','b'*40),('role','security')]:
   row=copy.deepcopy(result);row['structured_output'][key]=value;self.rejects([row])
 def test_missing_negative_boolean_or_oversized_usage_rejects(self):
  for value in [None,-1,True,1000000001]:
   row=copy.deepcopy(result);row['modelUsage'][m.MODEL]['inputTokens']=value;self.rejects([row])
 def test_findings_need_severity_safe_path_line_description(self):
  finding={'severity':'high','path':'.claude/scripts/example.py','line':14,'description':'Concrete defect.'}
  row=copy.deepcopy(result);row['structured_output']['findings']=[finding];self.assertEqual(len(m.validate([row],binding)['findings']),1)
  for field,value in [('severity','unknown'),('path','../outside'),('path','a\nTOKEN'),('line',True),('line',0),('description','')]:
   row=copy.deepcopy(result);row['structured_output']['findings']=[{**finding,field:value}];self.rejects([row])
 def test_prepared_context_binds_actual_git_objects_and_preserves_deletion(self):
  with tempfile.TemporaryDirectory() as folder:
   root=Path(folder);repo=root/'repo';repo.mkdir();temp=root/'temp';temp.mkdir()
   def git(*args):return subprocess.check_output(['git','-C',str(repo),*args],stderr=subprocess.DEVNULL,text=True).strip()
   git('init');git('config','user.name','Fixture');git('config','user.email','fixture@example.invalid')
   (repo/'file with spaces.py').write_text('old\n');git('add','.');git('commit','-m','initial');base=git('rev-parse','HEAD')
   (repo/'file with spaces.py').unlink();(repo/'new.py').write_text('new complete context\n'+'x'*5000);git('add','-A');git('update-index','--add','--cacheinfo','160000,'+'b'*40+',external');git('commit','-m','change');head=git('rev-parse','HEAD')
   event=root/'event.json';event.write_text(json.dumps({'repository':{'full_name':'example/project'},'pull_request':{'number':12,'head':{'sha':head},'base':{'sha':base}}}))
   env={**os.environ,'GITHUB_EVENT_PATH':str(event),'RUNNER_TEMP':str(temp)}
   preparer=script.with_name('prepare-claude-review.py')
   process=subprocess.run([sys.executable,'-I',str(preparer)],cwd=repo,env=env,capture_output=True,text=True);self.assertEqual(process.returncode,0,process.stderr)
   text=(temp/'claude-review-input.txt').read_text();self.assertIn('UNTRUSTED',text);self.assertIn(head,text);self.assertIn('old',text);self.assertIn('new complete context',text);self.assertIn('type=commit',text);self.assertTrue(all(len(line.encode())<=1600 for line in text.split('\n')))
   # Invalid revisions cannot become git options; stale context isn't published by this failed step.
   event.write_text(event.read_text().replace(head,'--help'));process=subprocess.run([sys.executable,'-I',str(preparer)],cwd=repo,env=env,capture_output=True);self.assertNotEqual(process.returncode,0)
   (repo/'huge.py').write_text('x'*(1024*1024+1));git('add','.');git('commit','-m','huge');huge=git('rev-parse','HEAD')
   event.write_text(json.dumps({'repository':{'full_name':'example/project'},'pull_request':{'number':12,'head':{'sha':huge},'base':{'sha':head}}}))
   (temp/'claude-review-input.txt').unlink()
   process=subprocess.run([sys.executable,'-I',str(preparer)],cwd=repo,env=env,capture_output=True,text=True)
   self.assertNotEqual(process.returncode,0);self.assertFalse((temp/'claude-review-input.txt').exists())
 def test_manual_security_dispatch_is_explicit_scan_not_unbound_review(self):
  text=Path('.github/workflows/claude-security.yml').read_text()
  self.assertIn("github.event_name == 'pull_request' &&",text)
  manual=text.split('  manual-security-scan:',1)[1]
  self.assertIn("if: github.event_name == 'workflow_dispatch'",manual)
  self.assertIn('contents: read',manual);self.assertNotIn('CLAUDE_CODE_OAUTH_TOKEN',manual)
  self.assertIn('/tmp/gitleaks git --redact',manual)
  review=text.split('  manual-security-scan:',1)[0]
  self.assertIn('Gitleaks (CLI — no org licence; T-143)\n        if: always()',review)
 def test_workflows_require_retention_and_upload_on_failure(self):
  for name in ['claude-review.yml','claude-security.yml']:
   text=(Path('.github/workflows')/name).read_text()
   self.assertNotIn('no review body yet',text)
   self.assertIn('id: claude_review',text)
   self.assertIn('run-claude-review.py',text);self.assertIn('if: always()',text)
   self.assertIn('@anthropic-ai/claude-code@2.1.295',text)
   self.assertIn('persist-credentials: false',text)
   self.assertNotIn('anthropics/claude-code-action',text);self.assertNotIn('ANTHROPIC_API_KEY',text)
   self.assertNotIn('id-token: write',text);self.assertNotIn('pull-requests: write',text)
   self.assertIn('actions/upload-artifact@',text)
unittest.main(verbosity=2)
PY
python3 -I .claude/scripts/test/claude-review-runner.py
