#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-6/AC-8: actual digest main selects fixed App context or untouched legacy roles."""
import copy,importlib.util,json,os,sys,tempfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
root=Path.cwd();script=root/'.claude/scripts/factory-git-state.py'
spec=importlib.util.spec_from_file_location('digest_cli',script);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
original_spec=importlib.util.spec_from_file_location;checks=0
with tempfile.TemporaryDirectory() as directory:
 base=Path(directory).resolve();fixed=base/'factory';fixed.mkdir();config_path=base/'config.json'
 policy={'repository':'org/repo','base_branch':'main'}
 files={'policy.json':policy,'receipt-trust.json':{'repository':'org/repo'},'receipt-store.json':{'repository':'org/repo','visibility':'public'},'receipt-archive-bootstrap.json':{'schema_version':2,'repository':'org/repo','branch':'state','writer_app_id':7},'receipt-policy-observations.json':{'repository':'org/repo'}}
 for name,value in files.items():(fixed/name).write_text(json.dumps(value))
 config={'enabled':True,'repository':'org/repo','state_repository':'org/repo','state_branch':'state','branch':'main','start':'2026-01-01T00:00:00Z','destination':'C1'}
 env={'PATH':os.environ['PATH'],'GITHUB_SERVER_URL':'https://github.com','GITHUB_REPOSITORY':'org/repo','GITHUB_REF':'refs/heads/main','GH_TOKEN':'source-synthetic','FACTORY_REPORTING_STATE_TOKEN':'legacy-synthetic','FACTORY_REPORTING_STATE_REPOSITORY':'org/repo','FACTORY_REPORTING_APP_ID':'7','FACTORY_REPORTING_APP_TOKEN':'writer-synthetic'}
 def invoke(flag,*,changes=None,config_changes=None,missing=None,expect_error=False):
  global checks
  selected=dict(env);selected.update(changes or {})
  if flag is not None:selected['FACTORY_REPORTING_APP_WRITER_ENABLED']=flag
  if missing:selected.pop(missing,None)
  value=dict(config,**(config_changes or {}));config_path.write_text(json.dumps(value));observed=[];loads=[]
  class Legacy:
   def __init__(self,repo,token=None):self.repo=repo;self.token=token
  def source(repo):return Legacy(repo,'source-constructor')
  def load_spec(name,path,*args,**kwargs):
   selected_spec=original_spec(name,path,*args,**kwargs)
   if Path(path).name=='factory-reporting-transport.py':
    loads.append(True);loader=selected_spec.loader
    class Loader:
     def create_module(self,spec):return loader.create_module(spec)
     def exec_module(self,module):
      loader.exec_module(module);attach=module.attach_reporting_context
      module.attach_reporting_context=lambda cfg:attach(cfg,checkout=base)
      def provider(command,*,env,**kwargs):
       observed.append(('provider',env['GH_TOKEN'],command[6]));return SimpleNamespace(returncode=0,stdout=b'{}',stderr=b'')
      module.process.run=provider
    selected_spec.loader=Loader()
   return selected_spec
  def run(cfg,report_api,state_api,client,path,now):
   if flag=='true':
    assert report_api is state_api and report_api.repo=='org/repo','App CLI did not share the routed role API'
    assert cfg['receipt_mode']=='durable' and cfg['pr_discovery_mode']=='resumable','App CLI omitted fixed selected modes'
    assert cfg['state_view']['approval_path']==str(fixed/'receipt-archive-bootstrap.json')
    report_api.request('repos/org/repo/actions/runs/1');state_api.request('repos/org/repo/git/trees/'+'a'*40)
   else:
    assert type(report_api) is Legacy and type(state_api) is Legacy and state_api.repo==cfg['state_repository']
    assert state_api.token==selected.get('FACTORY_REPORTING_STATE_TOKEN',selected.get('GH_TOKEN')) and report_api.token=='source-constructor'
    assert 'receipt_mode' not in cfg and 'pr_discovery_mode' not in cfg and not loads
   observed.append(('run',cfg));return {'status':'selected'}
  old_umask=os.umask(0o077);os.umask(old_umask)
  try:
   with patch.dict(os.environ,selected,clear=True),patch.object(sys,'argv',[str(script),'--config',str(config_path)]),patch.object(m,'API',Legacy),patch.object(m.digest.coordinator,'GitHub',source),patch.object(m.slack,'http_client',lambda cfg:None),patch.object(m,'run',run),patch.object(m.importlib.util,'spec_from_file_location',load_spec):
    try:m.main()
    except (ValueError,KeyError,OSError):
     assert expect_error,'unexpected CLI rejection';assert not any(row[0]=='run' for row in observed)
    else:
     assert not expect_error,'unsafe CLI accepted'
     if flag=='true':assert [row[1] for row in observed if row[0]=='provider']==['source-synthetic','writer-synthetic']
  finally:os.umask(old_umask)
  checks+=1
 invoke('true')
 for flag in (None,'false'):invoke(flag,config_changes={'state_repository':'other/state'})
 invoke('false',missing='FACTORY_REPORTING_STATE_TOKEN')
 for flag in ('TRUE','False','1',''):invoke(flag,expect_error=True)
 for field in ('GH_TOKEN','FACTORY_REPORTING_APP_TOKEN','FACTORY_REPORTING_APP_ID'):invoke('true',missing=field,expect_error=True)
 invoke('true',config_changes={'state_repository':'other/state'},expect_error=True)
 invoke('true',changes={'FACTORY_REPORTING_STATE_REPOSITORY':'other/state'},expect_error=True)
 invoke('true',changes={'GITHUB_SERVER_URL':'https://enterprise.invalid'},expect_error=True)
 invoke('true',changes={'GITHUB_REF':'refs/heads/feature'},expect_error=True)
 invoke('true',changes={'GITHUB_REPOSITORY':'ORG/repo'},expect_error=True)
 saved=(fixed/'receipt-store.json').read_bytes();(fixed/'receipt-store.json').unlink();invoke('true',expect_error=True)
 # Off remains usable even when all archive input files are absent.
 for path in fixed.iterdir():path.unlink()
 invoke('false');print(str(checks)+' actual digest main role/context/flag/native/legacy cases passed; offline providers only')
PY
