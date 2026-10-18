#!/usr/bin/env python3
"""AC-6/AC-8: categorical failures retain HTTP identity without private text."""
from pathlib import Path
import importlib.util,json,subprocess,sys,unittest
from types import SimpleNamespace
from unittest.mock import patch
R=Path(__file__).resolve().parents[3]
spec=importlib.util.spec_from_file_location('transport_diagnostic_test',R/'.claude/scripts/factory-reporting-transport.py');t=importlib.util.module_from_spec(spec);spec.loader.exec_module(t)
class SafeDiagnostics(unittest.TestCase):
 def test_failed_empty_stdout_preserves_status_and_call_bound(self):
  api=t.RoutedAPI('org/repo','offline-source','offline-state');reply=SimpleNamespace(returncode=1,stdout=b'',stderr=b'gh: PRIVATE-PAYLOAD fake-token (HTTP 403)')
  with patch.object(t.process,'run',return_value=reply):
   with self.assertRaises(ValueError) as caught:api.request('repos/org/repo')
  self.assertEqual(api.budget.calls,1);self.assertEqual(api.budget.bytes,0)
  self.assertEqual(getattr(caught.exception,'http_status',None),403)
  diagnostic=t.safe_diagnostic('checkpoint-or-delivery',caught.exception)
  self.assertEqual(diagnostic,{'stage':'checkpoint-or-delivery','error_class':'ReportingAPIError','http_status':403,'credential_role':'state'})
  self.assertNotIn('PRIVATE',json.dumps(diagnostic));self.assertNotIn('fake-token',str(caught.exception))
 def test_failed_output_is_charged_without_disclosure(self):
  api=t.RoutedAPI('org/repo','offline-source','offline-state');reply=SimpleNamespace(returncode=1,stdout=b'private',stderr=b'private (HTTP 429)')
  with patch.object(t.process,'run',return_value=reply):
   with self.assertRaises(ValueError) as caught:api.request('repos/org/repo')
  self.assertEqual(api.budget.bytes,7);self.assertEqual(t.safe_diagnostic('transport',caught.exception)['http_status'],429)
 def test_separate_wrapper_import_retains_categorical_http_status(self):
  spec=importlib.util.spec_from_file_location('separate_wrapper_transport',R/'.claude/scripts/factory-reporting-transport.py');other=importlib.util.module_from_spec(spec);spec.loader.exec_module(other)
  self.assertEqual(other.safe_diagnostic('transport',t.ReportingAPIError(b'private (HTTP 403)'))['http_status'],403)
 def test_unknown_error_stage_and_status_do_not_escape(self):
  error=type('PRIVATE_TOKEN_CLASS',(Exception,),{} )('private feedback text');error.http_status='private'
  self.assertEqual(t.safe_diagnostic('private-stage-text',error),{'stage':'unknown','error_class':'Exception','http_status':None})
 def test_provider_failure_kind_is_bounded_and_diagnostic_only(self):
  samples=[(b'gh: API rate limit exceeded for installation ID PRIVATE_ID (HTTP 403)','primary_api_rate_limit'),(b'gh: You have exceeded a secondary rate limit PRIVATE (HTTP 403)','secondary_api_rate_limit'),(b'gh: Resource not accessible by integration PRIVATE (HTTP 403)','integration_permission')]
  for raw,kind in samples:
   with self.subTest(kind=kind):
    record=t.safe_diagnostic('transport',t.ReportingAPIError(raw))
    self.assertEqual(record.get('api_failure_kind'),kind);self.assertNotIn('PRIVATE',json.dumps(record))
  unknown=t.ReportingAPIError(b'x'*2048+b'API rate limit exceeded (HTTP 403)')
  self.assertNotIn('api_failure_kind',t.safe_diagnostic('transport',unknown))
  unknown.api_failure_kind='PRIVATE_PAYLOAD';self.assertNotIn('api_failure_kind',t.safe_diagnostic('transport',unknown))
 def test_failure_role_does_not_expose_credentials_or_paths(self):
  for path,role in [('repos/org/repo','state'),('repos/org/repo/contents/private-path?ref=private','source')]:
   api=t.RoutedAPI('org/repo','PRIVATE_SOURCE_TOKEN','PRIVATE_STATE_TOKEN')
   with patch.object(t.process,'run',return_value=SimpleNamespace(returncode=1,stdout=b'',stderr=b'PRIVATE (HTTP 403)')):
    with self.assertRaises(ValueError) as caught:api.request(path)
   record=t.safe_diagnostic('transport',caught.exception);self.assertEqual(record.get('credential_role'),role)
   self.assertNotIn('PRIVATE',json.dumps(record));self.assertNotIn('private-path',json.dumps(record))
 def test_diagnostic_import_or_helper_failure_keeps_original_private(self):
  fixture = r"""
import importlib.util,json,runpy,sys,tempfile
from pathlib import Path
from unittest.mock import patch
original=importlib.util.spec_from_file_location;failure_mode=sys.argv[2]
class Loader:
 def __init__(self,wrapped):self.wrapped=wrapped
 def create_module(self,spec):return None
 def exec_module(self,module):
  self.wrapped.exec_module(module)
  def failed(*args):raise RuntimeError('DIAGNOSTIC_PRIVATE_CANARY')
  module.safe_diagnostic=failed
def selected(name,*args,**kwargs):
 if name in ('feedback_safe_diagnostic','alerts_safe_diagnostic'):
  if failure_mode=='import':raise RuntimeError('DIAGNOSTIC_PRIVATE_CANARY')
  spec=original(name,*args,**kwargs);spec.loader=Loader(spec.loader);return spec
 return original(name,*args,**kwargs)
with tempfile.TemporaryDirectory() as root:
 path=Path(root).resolve()/'config.json';path.write_text('{}');path.chmod(0o600)
 script=sys.argv[1];sys.argv=[script,'--config',str(path)]
 with patch('importlib.util.spec_from_file_location',side_effect=selected),patch('json.loads',side_effect=ValueError('ORIGINAL_PRIVATE_CANARY')):
  runpy.run_path(script,run_name='__main__')
"""
  for script in ['factory-hosted-feedback.py','factory-reporting-alerts.py']:
   for failure in ['import','helper']:
    run=subprocess.run([sys.executable,'-',str(R/'.claude/scripts'/script),failure],input=fixture,capture_output=True,text=True)
    self.assertEqual(run.returncode,2,run.stderr)
    self.assertNotIn('PRIVATE_CANARY',run.stderr);self.assertNotIn('Traceback',run.stderr)
    record=json.loads(run.stderr.splitlines()[-1]);self.assertEqual(record,{'stage':'diagnostic-unavailable','error_class':'Exception','http_status':None})
 def test_real_cli_config_failures_emit_only_fixed_categories(self):
  for script in ['factory-hosted-feedback.py','factory-reporting-alerts.py']:
   run=subprocess.run([sys.executable,str(R/'.claude/scripts'/script),'--config','/nonexistent-reporting-diagnostic-config'],capture_output=True,text=True)
   self.assertEqual(run.returncode,2);record=json.loads(run.stderr.splitlines()[-1]);self.assertEqual(record['stage'],'config');self.assertIn(record['error_class'],['ValueError','FileNotFoundError']);self.assertIsNone(record['http_status']);self.assertNotIn('/nonexistent',run.stderr);self.assertNotIn('Traceback',run.stderr)
if __name__=='__main__':unittest.main()
