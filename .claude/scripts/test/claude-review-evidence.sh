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
 def test_cli_retains_blocked_without_raw_error_and_handles_findings(self):
  with tempfile.TemporaryDirectory() as folder:
   root=Path(folder);event=root/'event.json';execution=root/'execution.json'
   event.write_text(json.dumps({'repository':{'full_name':binding['repository']},'pull_request':{'number':12,'head':{'sha':'a'*40}}}))
   env={**os.environ,'GITHUB_EVENT_PATH':str(event),'RUNNER_TEMP':str(root),'REVIEW_EXECUTION_FILE':str(execution),'REVIEW_ACTION_OUTCOME':'success','GITHUB_RUN_ID':'123','GITHUB_RUN_ATTEMPT':'2'}
   (root/'claude-review-input.txt').write_text('Fixture public context only')
   access={'type':'assistant','message':{'content':[{'type':'tool_use','id':'fixture-read','name':'Read','input':{'file_path':str(root/'claude-review-input.txt'),'offset':1,'limit':20}}]}}
   response={'type':'user','message':{'content':[{'type':'tool_result','tool_use_id':'fixture-read','content':'1\tFixture public context only'}]},'tool_use_result':{'type':'text','file':{'filePath':str(root/'claude-review-input.txt'),'startLine':1,'numLines':1,'totalLines':1,'content':'Fixture public context only'}}}
   def run(name,rows):
    execution.write_text(json.dumps([access,response]+rows));dest=root/name
    process=subprocess.run([sys.executable,'-I',str(script),'--role','code','--output',str(dest)],env=env,capture_output=True,text=True)
    return process,json.loads((dest/'review.json').read_text())
   process,saved=run('good',[result]);self.assertEqual(process.returncode,0);self.assertEqual(saved['head'],'a'*40)
   process,saved=run('missing',[]);self.assertEqual(process.returncode,1);self.assertEqual(saved['status'],'blocked')
   denied=copy.deepcopy(result);denied['permission_denials']=[{'input':'CANARY-PRIVATE-TOOL'}]
   process,saved=run('denied',[denied]);self.assertEqual(process.returncode,1);self.assertNotIn('CANARY',json.dumps(saved)+process.stdout+process.stderr)
   high=copy.deepcopy(result);high['structured_output']['findings']=[{'severity':'high','path':'source.py','line':1,'description':'Defect.'}]
   process,saved=run('high',[high]);self.assertEqual(process.returncode,1);self.assertEqual(saved['status'],'changes-required')
   original=access['message']['content'][0]['input']['file_path'];access['message']['content'][0]['input']['file_path']='/outside/CANARY-PRIVATE'
   process,saved=run('outside',[result]);self.assertEqual(process.returncode,1);self.assertNotIn('CANARY',json.dumps(saved)+process.stdout+process.stderr)
   access['message']['content'][0]['input']['file_path']=original
   execution.write_text('{"type":1,"type":2}')
   process=subprocess.run([sys.executable,'-I',str(script),'--role','code','--output',str(root/'duplicate')],env=env,capture_output=True)
   self.assertEqual(process.returncode,1)
   execution.write_text('['*2000+'0'+']'*2000)
   process=subprocess.run([sys.executable,'-I',str(script),'--role','code','--output',str(root/'deep')],env=env,capture_output=True,text=True)
   self.assertEqual(process.returncode,1);self.assertEqual(json.loads((root/'deep/review.json').read_text())['status'],'blocked');self.assertNotIn('Traceback',process.stderr)
 def test_access_requires_complete_untruncated_read_results(self):
  with tempfile.TemporaryDirectory() as folder:
   context=Path(folder)/'context.txt';context.write_text('first line\ncritical tail')
   call={'type':'assistant','message':{'content':[{'type':'tool_use','id':'read1','name':'Read','input':{'file_path':str(context),'offset':1,'limit':20}}]}}
   partial={'type':'user','message':{'content':[{'type':'tool_result','tool_use_id':'read1','content':'1\tfirst line'}]},'tool_use_result':{'type':'text','file':{'filePath':str(context),'startLine':1,'numLines':1,'totalLines':2,'content':'first line'}}}
   for rows in [[call],[call,partial]]:
    with self.assertRaises(ValueError):m.validate_access(rows,context)
   complete=copy.deepcopy(partial);complete['message']['content'][0]['content']='1\tfirst line\n2\tcritical tail';complete['tool_use_result']['file'].update(numLines=2,content='first line\ncritical tail')
   m.validate_access([call,complete],context)
   truncated=copy.deepcopy(complete);truncated['message']['content'][0]['content']='1\tfirst line\n2\tcritical...'
   with self.assertRaises(ValueError):m.validate_access([call,truncated],context)
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
 def test_preparation_failure_keeps_validator_available_for_blocked_report(self):
  text=Path('.github/workflows/claude-review.yml').read_text()
  block=text.split('      - name: Prepare exact-head review context and validator',1)[1].split('      - name:',1)[0].split('        run: |\n',1)[1]
  import textwrap
  with tempfile.TemporaryDirectory() as folder:
   root=Path(folder);event=root/'event.json';event.write_text('{}')
   env={**os.environ,'RUNNER_TEMP':str(root),'GITHUB_EVENT_PATH':str(event),'REVIEW_ACTION_OUTCOME':'skipped'}
   failed=subprocess.run(['bash','-e','-c',textwrap.dedent(block)],env=env,capture_output=True,text=True)
   self.assertNotEqual(failed.returncode,0);self.assertTrue((root/'retain-claude-review.py').is_file())
   retained=subprocess.run([sys.executable,'-I',str(root/'retain-claude-review.py'),'--role','code','--output',str(root/'blocked')],env=env,capture_output=True,text=True)
   self.assertEqual(retained.returncode,1);self.assertEqual(json.loads((root/'blocked/review.json').read_text())['status'],'blocked')
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
   self.assertIn('id: claude_review',text);self.assertIn('--json-schema',text)
   self.assertIn('retain-claude-review.py',text);self.assertIn('if: always()',text)
   self.assertIn('--setting-sources user',text);self.assertNotIn("--setting-sources ''",text)
   self.assertIn('actions/upload-artifact@',text)
   self.assertIn('steps.claude_review.outputs.execution_file',text)
   self.assertIn('REVIEW_ACTION_OUTCOME: ${{ steps.claude_review.outcome }}',text)
unittest.main(verbosity=2)
PY
