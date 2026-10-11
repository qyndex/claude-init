#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PYTEST'
from pathlib import Path
from contextlib import closing
import copy,hashlib,http.server,importlib.util,json,os,sqlite3,subprocess,sys,tempfile,threading,time,urllib.request,urllib.error
root=Path(sys.argv[1]);path=root/'.claude/scripts/factory-release.py';assert path.exists(),'protected release core absent'
spec=importlib.util.spec_from_file_location('release',path);release=importlib.util.module_from_spec(spec);spec.loader.exec_module(release)
A='a'*40;B='b'*40;C='c'*40;D='d'*40

def rejects(fn):
 try:fn()
 except (ValueError,OSError,sqlite3.Error):return
 raise AssertionError('unsafe production operation accepted')

def proof(sha):return {'merge_sha':sha,'delivery':json.dumps({'repository':'fixture/release','merge_sha':sha}),'provenance':json.dumps({'receipt':{'spec':'043'}})}

class Platform:
 def __init__(self):self.sha=A;self.previous=A;self.stage=100;self.count=0;self.effects={};self.lost=set();self.unknown=False;self.bad_health=False
 def call(self,action,request):
  identity={k:request[k] for k in ('schema_version','repository','service','environment','operation_id','sha','stage')};key=(request['operation_id'],request['stage'])
  if action=='observe':
   start=time.time();errors=0;latencies=[]
   for _ in range(20):
    before=time.monotonic()
    try:
     with urllib.request.urlopen(request['health_url'],timeout=2) as response:
      assert response.headers['X-Version'] in ({request['sha'],self.previous} if request['stage']==10 else {request['sha']})
      assert response.status==200
    except urllib.error.HTTPError as error:assert error.code==503;errors+=1
    latencies.append((time.monotonic()-before)*1000);time.sleep(.003)
   if self.bad_health:identity['service']='foreign'
   return {**identity,'metrics':{'samples':20,'errors':errors,'window_start':start,'window_end':time.time(),'p95_latency_ms':sorted(latencies)[18]}}
  if action=='lookup':
   if self.unknown or key not in self.effects:raise ValueError('effect remains unknown')
   return self.effects[key]['receipt']
  assert action in {'deploy','rollback'}
  # The fixture provider persists its effect independently of Release's SQLite.
  assert key not in self.effects,'controller blindly repeated deployment'
  self.previous=self.sha if action=='deploy' and request['stage']==10 else self.previous
  self.sha=request['sha'];self.stage=request['stage'];self.count=0
  value={**identity,'status':'present','deployment_id':str(len(self.effects)+1),'artifact_digest':hashlib.sha256(self.sha.encode()).hexdigest()}
  self.effects[key]={'receipt':value}
  if action in self.lost:self.lost.remove(action);raise ValueError('lost acknowledgement after actual effect')
  return value

with tempfile.TemporaryDirectory() as temporary:
 base=Path(temporary).resolve();base.chmod(0o700);platform=Platform()
 class Handler(http.server.BaseHTTPRequestHandler):
  def do_GET(self):
   platform.count+=1;sha=platform.sha if platform.count%10<platform.stage/10 else platform.previous
   self.send_response(503 if sha==C else 200);self.send_header('X-Version',sha);self.end_headers();self.wfile.write(sha.encode())
  def log_message(self,*args):pass
 server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
 try:
  executable=str(Path(sys.executable).resolve());runner=base/'adapter.py';runner.write_text('import json,os,sys\nassert "GH_TOKEN" not in os.environ and "FACTORY_SLACK_BOT_TOKEN" not in os.environ\nassert os.environ["PLATFORM_TOKEN"]=="fixture-only"\nprint(json.dumps({"ok":True}))\n')
  pins={executable:hashlib.sha256(Path(executable).read_bytes()).hexdigest(),str(runner):hashlib.sha256(runner.read_bytes()).hexdigest()}
  config={'enabled':True,'repository':'fixture/release','service':'web','environment':'production','adapter':{'argv':[executable,str(runner)],'pins':pins,'timeout':5},'credentials':{'PLATFORM_TOKEN':'DEPLOY_FIXTURE_TOKEN'},'stages':[10,100],'slo':{'min_samples':20,'window_seconds':.05,'max_error_rate':0,'p95_latency_ms':1000,'max_age_seconds':10},'baseline_sha':A,'health_url':f'http://127.0.0.1:{server.server_port}/health','eligible_specs':['043']}
  os.environ['DEPLOY_FIXTURE_TOKEN']='fixture-only';os.environ['GH_TOKEN']='must-not-leak';os.environ['FACTORY_SLACK_BOT_TOKEN']='must-not-leak'
  assert release.Adapter(config).call('lookup',{})=={'ok':True}
  runner.write_text(runner.read_text()+'# changed\n');rejects(lambda:release.Adapter(config).call('lookup',{}));runner.write_text(runner.read_text().replace('# changed\n',''))
  bad=copy.deepcopy(config);bad['adapter']['pins'].pop(str(runner));rejects(lambda:release.validate(bad))
  bad=copy.deepcopy(config);bad['enabled']=False;rejects(lambda:release.validate(bad))
  db=base/'release.sqlite';store=release.Release(db,config)
  rejects(lambda:store.run(proof('invalid'),platform));foreign=proof(B);foreign['delivery']=json.dumps({'repository':'foreign/repo','merge_sha':B});rejects(lambda:store.run(foreign,platform));assert not platform.effects
  # A different identity cannot mutate a nonempty private store.
  before=db.read_bytes();bad=copy.deepcopy(config);bad['repository']='foreign/repo';rejects(lambda:release.Release(db,bad));assert db.read_bytes()==before
  unrelated=base/'unrelated.sqlite'
  with closing(sqlite3.connect(unrelated)) as connection:connection.execute('CREATE TABLE keep(value TEXT)');connection.commit()
  unrelated.chmod(0o600);before=unrelated.read_bytes();rejects(lambda:release.Release(unrelated,config));assert unrelated.read_bytes()==before
  print('AC-1: disabled/missing pins, foreign delivery/store and unrelated state reject before deployment; actual pinned subprocess receives deployment-only credentials')
  result=store.run(proof(B),platform);assert result['status']=='healthy' and platform.sha==B and platform.stage==100 and len(platform.effects)==2
  assert release.Release(db,config).run(proof(B),platform)==result and len(platform.effects)==2
  with urllib.request.urlopen(config['health_url']) as response:assert response.headers['X-Version']==B
  assert result['independent_attestation'] is False
  print('AC-2: real HTTP healthy rollout measures every configured stage and duplicate authenticated-core delivery creates no additional effects')
  result=store.run(proof(C),platform);assert result['status']=='rolled-back' and result['rollback_sha']==B and platform.sha==B
  with urllib.request.urlopen(config['health_url']) as response:assert response.status==200 and response.headers['X-Version']==B
  assert len(platform.effects)==4
  with closing(sqlite3.connect(db)) as connection:
   receipts=connection.execute('SELECT receipt,health FROM release_stage_evidence').fetchall()
   assert sum(receipt is not None for receipt,health in receipts)==4
   assert any(health and json.loads(health)['errors']>0 for receipt,health in receipts)
   assert all(json.loads(receipt)['deployment_id'] for receipt,health in receipts if receipt)
  print('AC-3: actual HTTP 503 candidate breaches SLO, restores recorded known-good version and measures healthy rollback before confirmation')
  platform.lost={'deploy'};rejects(lambda:store.run(proof(D),platform));count=len(platform.effects);assert platform.sha==D
  platform.unknown=True;rejects(lambda:release.Release(db,config).run(proof(D),platform));rejects(lambda:store.run(proof('e'*40),platform));assert len(platform.effects)==count
  platform.unknown=False;result=release.Release(db,config).run(proof(D),platform);assert result['status']=='healthy' and len(platform.effects)==count+1
  platform.lost={'rollback'}
  # A fresh policy creates another independently identified unhealthy candidate.
  revised=copy.deepcopy(config);revised['slo']['max_age_seconds']=11;store=release.Release(db,revised)
  rejects(lambda:store.run(proof(C),platform));count=len(platform.effects);assert platform.sha==D
  with closing(sqlite3.connect(db)) as connection:assert connection.execute("SELECT count(*) FROM release_operations WHERE status='rollback-uncertain'").fetchone()[0]==1
  result=release.Release(db,revised).run(proof(C),platform);assert result['status']=='rolled-back' and result['rollback_sha']==D and len(platform.effects)==count
  print('AC-4: lost deploy/rollback acknowledgements survive SQLite reopen, unknown lookup fences other releases and reconciliation never blindly repeats actual effects')
  request=store.request('test',B,10);value={k:request[k] for k in ('schema_version','repository','service','environment','operation_id','sha','stage')};value.update(status='present',deployment_id='x',artifact_digest='a'*64);value['schema_version']=True;rejects(lambda:store.receipt(request,value))
  platform.bad_health=True;rejects(lambda:store.health(platform,request));platform.bad_health=False
  class Stale:
   def call(self,action,request):
    value=platform.call(action,request);value['metrics']['window_end']=time.time()-100;value['metrics']['window_start']=time.time()-101;return value
  rejects(lambda:store.health(Stale(),request))
  disabled=copy.deepcopy(config);disabled['enabled']=False
  config_path=base/'policy.json';config_path.write_text(json.dumps(disabled));config_path.chmod(0o600)
  result=subprocess.run([sys.executable,str(path),'--config',str(config_path),'--policy',str(config_path),'--db',str(db),'--run-id','1'],capture_output=True,text=True)
  assert result.returncode==2 and 'Credentials withheld' in result.stderr and 'fixture-only' not in result.stderr
  result=subprocess.run([sys.executable,str(path),'--help'],capture_output=True,text=True)
  assert result.returncode==0 and '--proof-file' not in result.stdout and '--adapter' not in result.stdout
  assert db.stat().st_mode&0o777==0o600
  print('AC-5: malformed identity and stale health cannot certify release; private state records exact outcomes without independent-review claims')
 finally:server.shutdown();server.server_close();thread.join()

PYTEST
