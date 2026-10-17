#!/usr/bin/env python3
"""Bounded actual-driver/fixed-CLI dispatch proof using a COPY of retained Git."""
import argparse
import ast
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import textwrap

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--snapshot',type=Path,required=True)
parser.add_argument('--provider',type=Path,required=True)
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args();source=Path.cwd().resolve();output=args.output.resolve();output.mkdir(parents=True,exist_ok=False)
code=output/'checkout';subprocess.run(['git','clone','--quiet','--no-hardlinks',str(source),str(code)],check=True)
subprocess.run(['git','-C',str(code),'checkout','--quiet','34f3f422c10cade29193787c4caf87a74b6cbf3a'],check=True)
state=output/'state';shutil.copytree(args.snapshot,state)
context=json.loads((state/'context.json').read_text());context.update(work=str(state/'git'),trust=str(state/'receipt-trust.json'),approval=str(state/'receipt-bootstrap.json'))
(state/'context.json').write_text(json.dumps(context));fixed=code/'factory'
for name,value in [('policy.json',context['policy']),('receipt-store.json',context['store'])]:(fixed/name).write_text(json.dumps(value))
shutil.copyfile(context['trust'],fixed/'receipt-trust.json');shutil.copyfile(context['approval'],fixed/'receipt-archive-bootstrap.json')
subprocess.run(['git','-C',str(code),'config','user.name','Fixture'],check=True);subprocess.run(['git','-C',str(code),'config','user.email','fixture@example.invalid'],check=True)
subprocess.run(['git','-C',str(code),'add','factory'],check=True);subprocess.run(['git','-C',str(code),'commit','-qm','bind offline fixed reporting context'],check=True)
fixture_sha=subprocess.check_output(['git','-C',str(code),'rev-parse','HEAD'],text=True).strip()
changed=subprocess.check_output(['git','-C',str(code),'diff','--name-only','34f3f422',fixture_sha],text=True).splitlines();assert changed and all(name.startswith('factory/') for name in changed)
config={'enabled':True,'repository':'org/repo','state_repository':'org/repo','state_branch':'factory-reporting-state','branch':'main','destination':'C1','start':'2026-10-15T00:00:00Z','bootstrap_sha':json.loads(Path(context['approval']).read_text())['bootstrap_sha']}
config_path=output/'config.json';config_path.write_text(json.dumps(config))
# Reuse existing exact provider definitions, excluding bootstrap/producer/capacity loop.
tree=ast.parse(args.provider.read_text());outer=next(n for n in tree.body if isinstance(n,ast.With))
header=[n for n in tree.body if n.lineno>1 and n is not outer]
select=[n for n in outer.body if (isinstance(n,(ast.FunctionDef,ast.ClassDef)) and n.name in ('git','out','State','PipelineState','HistoryState')) or n.lineno in (103,104,116,117,139,140,141,142)]
provider=next(n for n in outer.body if isinstance(n,ast.FunctionDef) and n.name=='http_provider')
setup="import os,sys,json,importlib.util,copy,sqlite3\nfrom pathlib import Path\nos.chdir("+repr(str(code))+')\ncontext=json.loads(Path('+repr(str(state/'context.json'))+').read_text())\n'
setup+='\n'.join(ast.unparse(n) for n in header)+'\n'
setup+="root=Path("+repr(str(state))+ ");work=Path(context['work']);trust=Path(context['trust']);approval=Path(context['approval']);policy=context['policy'];store=context['store'];stream=context['stream'];end=context['end'];ref='refs/heads/factory-reporting-state';branch='factory-reporting-state';oldpath='reports/'+'0'*64+'.json';initial=json.loads(approval.read_text())['bootstrap_sha'];tree=json.loads(approval.read_text())['bootstrap_tree'];conditions={'ref_name':{'include':[ref],'exclude':[]}}\n"
setup+='\n'.join(ast.unparse(n) for n in outer.body if n.lineno in (55,56))+'\n'
setup+='\n'.join(ast.unparse(n) for n in select)+'\n'
setup+="backend=HistoryState();source=runs(context['metadata'],policy,'2026-10-15T00:00:00Z',end);provider_bin=root/'blob-provider-bin';counts={'rest':0,'graphql':0};response_bytes=0\n"
setup+="original_spec=importlib.util.spec_from_file_location\nps=original_spec('fixture_process',scripts/'factory-bounded-process.py');process=importlib.util.module_from_spec(ps);ps.loader.exec_module(process);original=process.run\n"
setup+=ast.unparse(provider)+'\n'
setup+='''
metrics=[]
roles={'source':{'calls':0,'bytes':0,'rest':0,'graphql':0},'writer':{'calls':0,'bytes':0,'rest':0,'graphql':0}}
def provider_call(command,**kwargs):
 global response_bytes
 if command[:5]==['gh','api','--hostname','github.com','--method']:
  token=kwargs['env'].get('GH_TOKEN');assert token in ('offline-source-fixture','offline-writer-fixture'),'unknown fixture credential'
  role=roles['source' if token=='offline-source-fixture' else 'writer'];role['calls']+=1;role['graphql' if command[6]=='graphql' else 'rest']+=1
  result=http_provider(command,**kwargs);response_bytes+=len(result.stdout);role['bytes']+=len(result.stdout);return result
 return original(command,**kwargs)
class Delivery:
 def send(self,key,payload,destination):
  path=root/'synthetic-delivery-receipt.json'
  assert not path.exists(),'duplicate send'
  value={'key':key,'payload_sha256':hashlib.sha256(payload.encode()).hexdigest(),'destination':destination,'message_id':'1'}
  path.write_text(json.dumps(value));(root/'driver-payload.json').write_text(payload);return value
 def lookup(self,key):return {'receipt':json.loads((root/'synthetic-delivery-receipt.json').read_text()) if (root/'synthetic-delivery-receipt.json').exists() else None,'authoritative_absence':False}
def hooked_spec(name,path,*args,**kwargs):
 spec=original_spec(name,path,*args,**kwargs);filename=Path(path).name
 if filename in ('factory-bounded-process.py','factory-slack-digest.py','factory-reporting-transport.py'):
  loader=spec.loader
  class Loader:
   def create_module(self,spec):return loader.create_module(spec)
   def exec_module(self,module):
    loader.exec_module(module)
    if filename=='factory-bounded-process.py':module.run=provider_call
    elif filename=='factory-slack-digest.py':module.http_client=lambda config:object();module.transport=lambda *args:Delivery()
    else:
     create=module.create_api
     def tracked(env):
      value=create(env);metrics.append(value);return value
     module.create_api=tracked
  spec.loader=Loader()
 return spec
importlib.util.spec_from_file_location=hooked_spec
'''
setup_path=output/'provider-setup.py';setup_path.write_text(setup);compile(setup,str(setup_path),'exec')
bootstrap=output/'fixed-cli-bootstrap.py';bootstrap.write_text("import runpy,sys,json,os\nfrom pathlib import Path\n"+'exec(compile(Path('+repr(str(setup_path))+').read_text(),'+repr(str(setup_path))+",'exec'))\nsys.argv=["+repr(str(code/'.claude/scripts/factory-git-state.py'))+",'--config',"+repr(str(config_path))+"]\nimport datetime as clock\nclass FixedClock(clock.datetime):\n @classmethod\n def now(cls,tz=None):\n  value=cls(2026,10,16,12,tzinfo=clock.timezone.utc);return value.astimezone(tz) if tz else value.replace(tzinfo=None)\nclock.datetime=FixedClock\ntry:\n runpy.run_path(sys.argv[0],run_name='__main__')\nfinally:\n value={'pid':os.getpid(),'calls':sum(x.budget.calls for x in metrics),'bytes':sum(x.budget.bytes for x in metrics),'provider':counts,'provider_response_bytes':response_bytes,'roles':roles}\n with Path("+repr(str(output/'children.jsonl'))+").open('a') as f:f.write(json.dumps(value)+'\\n')\n")
env=dict(os.environ,GITHUB_SERVER_URL='https://github.com',GITHUB_REPOSITORY='org/repo',GITHUB_REF='refs/heads/main',GITHUB_SHA=fixture_sha,FACTORY_REPORTING_APP_WRITER_ENABLED='true',FACTORY_REPORTING_APP_ID='7',FACTORY_REPORTING_STATE_REPOSITORY='org/repo',FACTORY_REPORTING_APP_TOKEN='offline-writer-fixture',GH_TOKEN='offline-source-fixture')
os.environ.clear();os.environ.update(env)
namespace={};exec(compile(setup,str(setup_path),'exec'),namespace)
ds=namespace['original_spec']('actual_driver',code/'.claude/scripts/factory-reporting-driver.py');driver=__import__('importlib.util').util.module_from_spec(ds);ds.loader.exec_module(driver)
launches=[]
def driver_process(command,**kwargs):
 if len(command)==5 and command[1:4]==['-I',str(code/'.claude/scripts/factory-git-state.py'),'--config']:
  assert command[4]==str(config_path);launches.append(command)
  return namespace['original']([command[0],'-I',str(bootstrap)],**kwargs)
 return namespace['provider_call'](command,**kwargs)
driver.PROCESS.run=driver_process
def git_state(*arguments):return subprocess.check_output(['git','-C',str(state/'git'),*arguments])
before=git_state('rev-parse','refs/heads/factory-reporting-state').decode().strip()
prior_receipt=(state/'synthetic-delivery-receipt.json').read_bytes()
prior_tree=git_state('ls-tree','-r',before).decode().splitlines()
protected={line.split('\t',1)[1]:line.split('\t',1)[0] for line in prior_tree if line.split('\t',1)[1].startswith('reports/')}
assert protected and json.loads(prior_receipt)['message_id']=='1'
text=io.StringIO()
with contextlib.redirect_stdout(text):result=driver.drive(config_path,max_seconds=180,max_invocations=1)
after=git_state('rev-parse','refs/heads/factory-reporting-state').decode().strip()
assert result['status']=='not-due' and result['invocations']==1 and result['observer_calls']==0,(result,text.getvalue())
assert (state/'synthetic-delivery-receipt.json').read_bytes()==prior_receipt
assert not (state/'driver-payload.json').exists(),'confirmed state resent payload'
for path,identity in protected.items():
 assert git_state('ls-tree',after,'--',path).decode().strip().split('\t',1)[0]==identity,('opaque/report changed',path)
children=[json.loads(line) for line in (output/'children.jsonl').read_text().splitlines()];assert len(children)==1
assert all(0<c['calls']<=2048 and 0<c['bytes']<=33554432 for c in children)
assert all(sum(r['calls'] for r in c['roles'].values())==c['provider']['rest']+c['provider']['graphql'] and sum(r['bytes'] for r in c['roles'].values())==c['provider_response_bytes'] for c in children)
production={str(path.relative_to(source)):hashlib.sha256(path.read_bytes()).hexdigest() for path in (source/'.claude/scripts').glob('*.py')}
assert all(hashlib.sha256((code/path).read_bytes()).hexdigest()==value for path,value in production.items())
proof={'production_source':'34f3f422c10cade29193787c4caf87a74b6cbf3a','production_sha256':production,'fixture_source':fixture_sha,'fixture_changes':changed,'job':result,'children':children,'fixed_launches':launches,'before':before,'after':after,'prior_receipt_sha256':hashlib.sha256(prior_receipt).hexdigest(),'protected_report_paths':len(protected),'clock_seam':'external datetime.now fixed to2026-10-16T12:00:00Z; actualmain computes due cutoff','dispatch_seam':'fixed child redirected only to fresh Python-I bootstrap running byte-identical CLI __main__; gh/Slack I/O offline','producer_regenerated':False,'seeded_ready':False,'confirmed_no_send':True,'full_cadence_proven':False,'provider_fixture_sha256':hashlib.sha256(args.provider.read_bytes()).hexdigest()}
(output/'result.json').write_text(json.dumps(proof,indent=2)+'\n');print(json.dumps({'status':'confirmed-driver-quiet-pass','children':children,'job':result,'output':str(output)},indent=2))
