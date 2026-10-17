#!/usr/bin/env bash
# Spec014 AC-6/8: offline CLI credential selection and fixed context boundaries.
set -euo pipefail
cd "$(dirname "$0")/../../.."
"${FACTORY_TEST_PYTHON:-python3}" - <<'PY'
from pathlib import Path
import base64,contextlib,copy,importlib.util,io,json,os,subprocess,sys,tempfile
ROOT=Path.cwd();scripts=ROOT/'.claude/scripts'
HEAD=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
base={'enabled':True,'feedback_enabled':True,'monitor_enabled':True,'repository':'org/repo','state_repository':'org/repo','branch':'main','state_branch':'factory-reporting-state','bootstrap_sha':'b'*40,'destination':'C1','team_id':'T1','start':'2026-10-01T00:00:00Z','feedback_key_id':'fixture-v1','feedback_bootstrap_sha':'b'*40}
env={'PATH':os.environ['PATH'],'HOME':os.environ['HOME'],'GITHUB_REPOSITORY':'org/repo','GITHUB_SERVER_URL':'https://github.com','GITHUB_API_URL':'https://api.github.com','GITHUB_ACTIONS':'true','RUNNER_ENVIRONMENT':'github-hosted','GITHUB_REF':'refs/heads/main','GITHUB_SHA':HEAD,'GITHUB_WORKFLOW_SHA':HEAD,'GITHUB_WORKFLOW_REF':'org/repo/.github/workflows/factory-reporting-queue.yml@refs/heads/main','GITHUB_RUN_ID':'900','GITHUB_RUN_ATTEMPT':'2','GITHUB_EVENT_NAME':'schedule','FACTORY_REPORTING_ENABLED':'true','FACTORY_REPORTING_PROFILE':'github-hosted','FACTORY_REPORTING_QUEUE_ENABLED':'true','FACTORY_REPORTING_BRANCH':'main','FACTORY_REPORTING_CHANNEL':'C1','FACTORY_REPORTING_TEAM_ID':'T1','FACTORY_REPORTING_START':'2026-10-01T00:00:00Z','FACTORY_REPORTING_ATTACHMENTS_ENABLED':'false','FACTORY_REPORTING_STATE_REPOSITORY':'org/repo','FACTORY_REPORTING_STATE_BRANCH':'factory-reporting-state','FACTORY_REPORTING_QUEUE_BOOTSTRAP_SHA':'b'*40,'FACTORY_REPORTING_QUEUE_INITIALIZE':'false','FACTORY_REPORTING_QUEUE_GRACE_MINUTES':'60','FACTORY_REPORTING_POLICY_APPROVALS':'{}','FACTORY_SLACK_BOT_TOKEN':'xoxb-fixture','GH_TOKEN':'source-fixture','FACTORY_REPORTING_STATE_TOKEN':'legacy-fixture','FACTORY_REPORTING_APP_ID':'5340785','FACTORY_FEEDBACK_STATE_KEY':base64.b64encode(b'x'*32).decode()}
files=('factory-reporting-alerts.py','factory-reporting-queue.py','factory-hosted-feedback.py','factory-reporting-watchdog.py')
fixed=ROOT/'factory'
values={'policy.json':{'repository':'org/repo','base_branch':'main'},
        'receipt-trust.json':{'schema_version':1,'repository':'org/repo','profiles':[],'legacy_revisions':{}},
        'receipt-archive-bootstrap.json':{'schema_version':2,'repository':'org/repo','repository_id':101,'private':False,'branch':'factory-reporting-state','writer_app_id':5340785,'bootstrap_sha':'b'*40},
        'receipt-store.json':{'repository':'org/repo','visibility':'public'},
        'receipt-policy-observations.json':{'schema_version':1,'repository':'org/repo','repository_id':101,'branch':'factory-reporting-state','writer_app_id':5340785}}
originals={name:((fixed/name).read_bytes() if (fixed/name).exists() else None) for name in values}
def install_values(selected=values):
 for name,value in selected.items():(fixed/name).write_text(json.dumps(value))
saved_env=dict(os.environ);saved_argv=sys.argv[:];failures=[];count=0
try:
 with tempfile.TemporaryDirectory() as temporary:
  private=Path(temporary).resolve();private.chmod(0o700);config_path=private/'config.json';record=private/'calls'
  stub=private/'gh';stub.write_text('#!/usr/bin/env python3\nimport json,os\nfrom pathlib import Path\nwith Path(os.environ["HOME"],"calls").open("a") as output:output.write(json.dumps({"token":os.environ.get("GH_TOKEN")})+"\\n")\nprint("{}")\n');stub.chmod(0o755)
  env.update(HOME=str(private),PATH=str(private)+os.pathsep+env['PATH'])
  install_values()
  for filename in files:
   spec=importlib.util.spec_from_file_location('cli_'+filename.replace('-','_'),scripts/filename);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
   seen=[]
   def entry(config,api,*args,**kwargs):seen.append((copy.deepcopy(config),api));return {'missed_delivery':False}
   if filename=='factory-reporting-queue.py':
    def entry_queue(local_env,api,*args,**kwargs):seen.append((m.build_config(local_env),api));return {}
    m.protected_entry=entry_queue
   elif filename=='factory-reporting-watchdog.py':m.inspect=entry
   else:m.run=entry
   for state_token in ('legacy-fixture',''):
    config_path.write_text(json.dumps(base));config_path.chmod(0o600)
    os.environ.clear();os.environ.update(env,FACTORY_REPORTING_STATE_TOKEN=state_token)
    sys.argv=['cli'] if filename=='factory-reporting-queue.py' else ['cli','--config',str(config_path)]
    seen.clear()
    with contextlib.redirect_stdout(io.StringIO()):m.main()
    assert len(seen)==1
    api=seen[0][1]
    if filename=='factory-reporting-queue.py':assert api.actions.token=='source-fixture' and api.state.token==(state_token or 'source-fixture')
    else:assert api.token==(state_token or 'source-fixture')
    count+=1
   if filename!='factory-reporting-queue.py':
    for state_repo in ('state-owner/report-state','Org/Repo'):
     config=dict(base,state_repository=state_repo);config_path.write_text(json.dumps(config));config_path.chmod(0o600)
     os.environ.clear();os.environ.update(env,FACTORY_REPORTING_APP_WRITER_ENABLED='false');seen.clear()
     with contextlib.redirect_stdout(io.StringIO()):m.main()
     assert len(seen)==1 and seen[0][0]==config
     expected_repo=base['repository'] if filename=='factory-reporting-alerts.py' else state_repo
     assert seen[0][1].repo==expected_repo and seen[0][1].token=='legacy-fixture';count+=1
   else:
    os.environ.clear();os.environ.update(env,FACTORY_REPORTING_APP_WRITER_ENABLED='false',FACTORY_REPORTING_STATE_REPOSITORY='state-owner/report-state');seen.clear()
    try:m.main()
    except ValueError as error:assert str(error)=='queue repository differs'
    else:raise AssertionError('legacy queue foreign-repository rejection changed')
    assert not seen;count+=1
   for flag in ('TRUE','true'):
    os.environ.clear();os.environ.update(env,FACTORY_REPORTING_APP_WRITER_ENABLED=flag)
    config_path.write_text(json.dumps(base));config_path.chmod(0o600);seen.clear()
    try:
     with contextlib.redirect_stdout(io.StringIO()):m.main()
    except ValueError:pass
    else:failures.append(filename+' accepted '+('malformed flag' if flag=='TRUE' else 'missing selected App token'))
    count+=1
   # Actual shared helper + transport, with only effectful consumer entry replaced.
   install_values();config_path.write_text(json.dumps(base));config_path.chmod(0o600)
   os.environ.clear();os.environ.update(env,FACTORY_REPORTING_APP_WRITER_ENABLED='true',FACTORY_REPORTING_APP_TOKEN='writer-fixture');seen.clear()
   with contextlib.redirect_stdout(io.StringIO()):m.main()
   assert len(seen)==1
   captured,api=seen[0]
   context=captured['reporting'] if filename=='factory-reporting-queue.py' else captured
   expected_view={'mode':'archive','approval_path':str(fixed/'receipt-archive-bootstrap.json')}
   if filename=='factory-reporting-queue.py':
    assert set(context)=={'enabled','repository','state_repository','branch','destination','team_id','start','attachments_enabled'}
    assert captured['storage']['state_view']==expected_view
   else:
    assert context['state_view']==expected_view and context['receipt_mode']=='durable'
    assert context.get('pr_discovery_mode')=='resumable','selected CLI did not forward resumable PR discovery'
    assert context['receipt_archive']['trust_mode']=='profile'
   assert hasattr(api,'budget') and api.budget.calls==0
   before=len(record.read_text().splitlines()) if record.exists() else 0
   api.request('repos/org/repo/actions/runs/7');api.request('repos/org/repo/git/ref/heads/state')
   rows=[json.loads(line) for line in record.read_text().splitlines()[before:]]
   assert [row['token'] for row in rows]==['source-fixture','writer-fixture'] and api.budget.calls==2;count+=1
   for field,change in (('missing-fixed',None),('state-branch','foreign'),('writer-id',5340786),('fixed-repository','foreign/repo'),('selected-api','foreign/repo')):
    install_values();config=copy.deepcopy(base);local_env=dict(env,FACTORY_REPORTING_APP_WRITER_ENABLED='true',FACTORY_REPORTING_APP_TOKEN='writer-fixture')
    if field=='missing-fixed':(fixed/'receipt-store.json').unlink()
    elif field=='state-branch':
     config['state_branch']=change
     if filename=='factory-reporting-queue.py':local_env['FACTORY_REPORTING_STATE_BRANCH']=change
    elif field=='writer-id':
     value=dict(values['receipt-archive-bootstrap.json'],writer_app_id=change);(fixed/'receipt-archive-bootstrap.json').write_text(json.dumps(value))
    elif field=='fixed-repository':
     value=dict(values['receipt-store.json'],repository=change);(fixed/'receipt-store.json').write_text(json.dumps(value))
    else:
     config.update(repository=change,state_repository=change)
     for name,value in values.items():(fixed/name).write_text(json.dumps(dict(value,repository=change)))
    config_path.write_text(json.dumps(config));config_path.chmod(0o600);seen.clear();os.environ.clear();os.environ.update(local_env)
    try:
     with contextlib.redirect_stdout(io.StringIO()):m.main()
    except ValueError:pass
    else:failures.append(filename+' accepted context '+field)
    if seen:failures.append(filename+' entered consumer with rejected context '+field)
    count+=1
   install_values()
 assert not failures,failures
 print(str(count)+' actual CLI credential-selection cases passed; no native effects')
finally:
 sys.argv=saved_argv;os.environ.clear();os.environ.update(saved_env)
 for name,raw in originals.items():
  if raw is None:(fixed/name).unlink(missing_ok=True)
  else:(fixed/name).write_bytes(raw)
PY
