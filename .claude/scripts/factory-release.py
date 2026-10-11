#!/usr/bin/env python3
"""Protected platform-neutral release core; uncertain deployment effects never replay blindly."""
from contextlib import contextmanager,closing
import argparse
import fcntl
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import sqlite3
import stat
import tempfile
import time
from urllib.parse import urlparse


def require(condition,message):
    if not condition:raise ValueError(message)


def canonical(value):return json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False)


def pairs(items):
    result={}
    for key,value in items:require(key not in result,'duplicate release field');result[key]=value
    return result


def validate(config):
    require(isinstance(config,dict) and set(config)=={'enabled','repository','service','environment','adapter','credentials','stages','slo','baseline_sha','health_url','eligible_specs'},'release policy fields invalid')
    require(config['enabled'] is True,'production release disabled')
    require(isinstance(config['repository'],str) and re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',config['repository']),'release repository invalid')
    for key in ('service','environment'):require(isinstance(config[key],str) and re.fullmatch(r'[A-Za-z0-9_.-]{1,64}',config[key]),'service/environment invalid')
    require(isinstance(config['baseline_sha'],str) and re.fullmatch(r'[a-f0-9]{40}',config['baseline_sha']),'approved baseline required')
    stages=config['stages'];require(isinstance(stages,list) and 1<=len(stages)<=10 and all(type(stage) is int and 1<=stage<=100 for stage in stages) and stages==sorted(set(stages)) and stages[-1]==100,'progressive stages invalid')
    require(isinstance(config['eligible_specs'],list) and 1<=len(config['eligible_specs'])<=100 and all(isinstance(sid,str) and re.fullmatch(r'[0-9]{3,}',sid) for sid in config['eligible_specs']),'explicit deployable spec mapping required')
    require(isinstance(config['health_url'],str),'health URL type invalid')
    endpoint=urlparse(config['health_url']);require(endpoint.scheme=='https' or (endpoint.scheme=='http' and endpoint.hostname in {'127.0.0.1','localhost','::1'}),'approved health URL required')
    require(endpoint.hostname and not endpoint.username and not endpoint.password and not endpoint.query and not endpoint.fragment,'health URL cannot embed credentials')
    slo=config['slo'];require(isinstance(slo,dict) and set(slo)=={'min_samples','window_seconds','max_error_rate','p95_latency_ms','max_age_seconds'},'complete service SLO required')
    require(type(slo['min_samples']) is int and 1<=slo['min_samples']<=10000,'sample floor invalid')
    for field,lower,upper in [('window_seconds',.01,3600),('max_error_rate',0,1),('p95_latency_ms',.01,60000),('max_age_seconds',1,3600)]:
        require(type(slo[field]) in {float,int} and math.isfinite(slo[field]) and lower<=slo[field]<=upper,'SLO bounds invalid')
    adapter=config['adapter'];require(isinstance(adapter,dict) and set(adapter)=={'argv','pins','timeout'} and isinstance(adapter['argv'],list) and 1<=len(adapter['argv'])<=20 and all(isinstance(arg,str) and len(arg)<=20000 and '\0' not in arg for arg in adapter['argv']) and Path(adapter['argv'][0]).is_absolute() and isinstance(adapter['pins'],dict) and adapter['argv'][0] in adapter['pins'] and type(adapter['timeout']) is int and 1<=adapter['timeout']<=60,'pinned adapter required')
    require(isinstance(adapter['pins'],dict) and 1<=len(adapter['pins'])<=20,'adapter pins invalid')
    for arg in adapter['argv']:
        if Path(arg).is_absolute():require(arg in adapter['pins'],'absolute adapter inputs must be pinned')
    for name,digest in adapter['pins'].items():require(isinstance(name,str) and Path(name).is_absolute() and isinstance(digest,str) and re.fullmatch(r'[a-f0-9]{64}',digest),'adapter digest invalid')
    require(isinstance(config['credentials'],dict) and len(config['credentials'])<=20,'deployment credential mapping invalid')
    for target,source in config['credentials'].items():require(isinstance(target,str) and isinstance(source,str) and re.fullmatch(r'[A-Z][A-Z0-9_]{0,99}',target) and not target.startswith(('FACTORY_','CLAUDE_','ANTHROPIC_')) and target not in {'GH_TOKEN','GITHUB_TOKEN','HOME','PATH','LD_PRELOAD','LD_LIBRARY_PATH','DYLD_INSERT_LIBRARIES','PYTHONPATH','PYTHONHOME','BASH_ENV','ENV'} and re.fullmatch(r'DEPLOY_[A-Z0-9_]{1,99}',source),'deployment-only secret references required')


class Adapter:
    def __init__(self,config):
        self.config=config
        spec=importlib.util.spec_from_file_location('bounded',Path(__file__).with_name('factory-bounded-process.py'));self.bounded=importlib.util.module_from_spec(spec);spec.loader.exec_module(self.bounded)
    def check_pins(self):
        for name,digest in self.config['adapter']['pins'].items():
            path=Path(name);require(path.resolve()==path and path.is_file() and 0<path.stat().st_size<=100_000_000 and hashlib.sha256(path.read_bytes()).hexdigest()==digest,'adapter pin changed')
            require(Path(__file__).resolve().parents[2] not in path.parents,'deployment adapter cannot come from candidate checkout')
    def call(self,action,request):
        self.check_pins()
        with tempfile.TemporaryDirectory(prefix='factory-deployment-') as directory:
            env={'PATH':os.defpath,'HOME':directory,'LC_ALL':'C'}
            for target,source in self.config['credentials'].items():require(bool(os.environ.get(source)),'deployment credential missing');env[target]=os.environ[source]
            result=self.bounded.run([*self.config['adapter']['argv'],action,canonical(request)],env=env,cwd=directory,timeout=self.config['adapter']['timeout'])
        self.check_pins()
        require(result.returncode==0,'deployment adapter acknowledgement unavailable')
        return json.loads(result.stdout,object_pairs_hook=pairs)


class Release:
    def __init__(self,path,config):
        validate(config);self.path=Path(path);self.config=config
        require(self.path.is_absolute() and self.path.resolve()==self.path and self.path.parent.stat().st_uid==os.getuid() and stat.S_IMODE(self.path.parent.stat().st_mode)==0o700,'release store must be private canonical storage')
        require(Path(__file__).resolve().parents[2] not in self.path.parents,'release database cannot be candidate-controlled')
        if self.path.exists():require(self.path.stat().st_nlink==1 and self.path.is_file() and self.path.stat().st_uid==os.getuid() and stat.S_IMODE(self.path.stat().st_mode)==0o600,'release database owner/mode invalid')
        with closing(sqlite3.connect(self.path)) as db:
            tables={row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")}
            require(not db.execute("SELECT 1 FROM sqlite_master WHERE type IN ('view','trigger')").fetchone(),'unexpected release database objects')
            binding=canonical([config['repository'],config['service'],config['environment']])
            if tables:
                require(tables=={'release_binding','release_operations','release_stage_evidence'},'foreign/unbound release database')
                old=db.execute('SELECT identity FROM release_binding WHERE id=1').fetchall()
                require(len(old)==1 and old[0][0]==binding,'foreign release namespace')
            self.path.chmod(0o600);db.executescript('CREATE TABLE IF NOT EXISTS release_binding(id INTEGER PRIMARY KEY CHECK(id=1),identity TEXT NOT NULL,known_good TEXT NOT NULL); CREATE TABLE IF NOT EXISTS release_operations(id TEXT PRIMARY KEY,sha TEXT NOT NULL,policy TEXT NOT NULL,status TEXT NOT NULL,stage INTEGER NOT NULL,rollback_sha TEXT NOT NULL,artifact TEXT,result TEXT,receipt TEXT); CREATE TABLE IF NOT EXISTS release_stage_evidence(operation_id TEXT,stage INTEGER,receipt TEXT,health TEXT,PRIMARY KEY(operation_id,stage));')
            binding=canonical([config['repository'],config['service'],config['environment']]);old=db.execute('SELECT identity FROM release_binding WHERE id=1').fetchone();require(old is None or old[0]==binding,'foreign release namespace')
            db.execute('INSERT OR IGNORE INTO release_binding VALUES(1,?,?)',(binding,config['baseline_sha']));db.commit()
    @contextmanager
    def transaction(self):
        with closing(sqlite3.connect(self.path,timeout=10)) as db:
            db.row_factory=sqlite3.Row;db.execute('BEGIN IMMEDIATE')
            try:yield db;db.commit()
            except BaseException:db.rollback();raise
    def request(self,identity,sha,stage):return {'schema_version':1,'repository':self.config['repository'],'service':self.config['service'],'environment':self.config['environment'],'operation_id':identity,'sha':sha,'stage':stage,'health_url':self.config['health_url'],'slo':self.config['slo']}
    def receipt(self,request,value):
        keys={'schema_version','repository','service','environment','operation_id','sha','stage'}
        require(isinstance(value,dict) and set(value)==keys|{'status','deployment_id','artifact_digest'} and all(type(value[key]) is type(request[key]) and value[key]==request[key] for key in keys),'deployment receipt identity differs')
        require(value['status']=='present' and isinstance(value['deployment_id'],str) and 0<len(value['deployment_id'])<=200 and isinstance(value['artifact_digest'],str) and re.fullmatch(r'[a-f0-9]{64}',value['artifact_digest']),'deployment effect not confirmed')
        return value
    def health(self,adapter,request):
        value=adapter.call('observe',request);keys={'schema_version','repository','service','environment','operation_id','sha','stage'}
        require(isinstance(value,dict) and set(value)==keys|{'metrics'} and all(type(value[key]) is type(request[key]) and value[key]==request[key] for key in keys),'service health identity differs')
        metrics=value['metrics'];require(isinstance(metrics,dict) and set(metrics)=={'samples','errors','window_start','window_end','p95_latency_ms'},'complete health metrics required')
        require(type(metrics['samples']) is int and self.config['slo']['min_samples']<=metrics['samples']<=10000 and type(metrics['errors']) is int and 0<=metrics['errors']<=metrics['samples'],'health sample floor invalid')
        for key in ('window_start','window_end','p95_latency_ms'):require(type(metrics[key]) in {int,float} and math.isfinite(metrics[key]),'health metric numeric type invalid')
        now=time.time();require(0<=metrics['p95_latency_ms']<=600000 and metrics['window_end']-metrics['window_start']>=self.config['slo']['window_seconds'] and 0<=now-metrics['window_end']<=self.config['slo']['max_age_seconds'],'health window missing/stale')
        self.evidence(request,'health',metrics)
        require(metrics['errors']/metrics['samples']<=self.config['slo']['max_error_rate'] and metrics['p95_latency_ms']<=self.config['slo']['p95_latency_ms'],'service SLO breached')
        return metrics
    def evidence(self,request,kind,value):
        require(kind in {'receipt','health'},'release evidence kind invalid')
        identity=request['operation_id'];stage=request['stage'];document=canonical(value)
        with self.transaction() as db:
            old=db.execute('SELECT receipt FROM release_stage_evidence WHERE operation_id=? AND stage=?',(identity,stage)).fetchone()
            if kind=='receipt' and old and old[0] is not None:require(old[0]==document,'confirmed deployment receipt changed')
            db.execute('INSERT OR IGNORE INTO release_stage_evidence(operation_id,stage) VALUES(?,?)',(identity,stage))
            db.execute('UPDATE release_stage_evidence SET '+kind+'=? WHERE operation_id=? AND stage=?',(document,identity,stage))
    def update(self,identity,**fields):
        require(set(fields)<={'status','stage','artifact','result','receipt'},'release update invalid')
        with self.transaction() as db:db.execute('UPDATE release_operations SET '+','.join(key+'=?' for key in fields)+' WHERE id=?',(*fields.values(),identity))
    def run(self,proof,adapter):
        require(isinstance(proof,dict) and isinstance(proof.get('merge_sha'),str) and re.fullmatch(r'[a-f0-9]{40}',proof['merge_sha']),'authenticated merge identity required')
        delivery=json.loads(proof['delivery']);provenance=json.loads(proof['provenance']);require(delivery['repository']==self.config['repository'] and delivery['merge_sha']==proof['merge_sha'] and provenance['receipt']['spec'] in self.config['eligible_specs'],'delivery outside protected service policy')
        policy=hashlib.sha256(canonical(self.config).encode()).hexdigest();identity=hashlib.sha256(canonical([self.config['repository'],self.config['service'],self.config['environment'],proof['merge_sha'],policy]).encode()).hexdigest()
        lock=self.path.with_suffix('.release.lock');require(not lock.is_symlink(),'release lock symlink invalid');fd=os.open(lock,os.O_CREAT|os.O_RDWR|getattr(os,'O_NOFOLLOW',0),0o600)
        try:
            info=os.fstat(fd);require(stat.S_ISREG(info.st_mode) and info.st_uid==os.getuid() and info.st_nlink==1 and stat.S_IMODE(info.st_mode)==0o600,'release lock must be private')
            fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)
            with self.transaction() as db:
                old=db.execute('SELECT * FROM release_operations WHERE id=?',(identity,)).fetchone()
                require(not db.execute("SELECT 1 FROM release_operations WHERE id!=? AND status NOT IN ('healthy','rolled-back','baseline-blocked')",(identity,)).fetchone(),'another deployment effect unresolved')
                if old is None:
                    baseline=db.execute('SELECT known_good FROM release_binding WHERE id=1').fetchone()[0];db.execute("INSERT INTO release_operations VALUES(?,?,?,'pending',0,?,NULL,NULL,NULL)",(identity,proof['merge_sha'],policy,baseline));old=db.execute('SELECT * FROM release_operations WHERE id=?',(identity,)).fetchone()
                row=dict(old)
                if row['status']=='baseline-blocked':
                    baseline=db.execute('SELECT known_good FROM release_binding WHERE id=1').fetchone()[0]
                    db.execute('UPDATE release_operations SET rollback_sha=? WHERE id=?',(baseline,identity));row['rollback_sha']=baseline
            require(row['sha']==proof['merge_sha'] and row['policy']==policy and isinstance(row['rollback_sha'],str) and re.fullmatch(r'[a-f0-9]{40}',row['rollback_sha']) and type(row['stage']) is int and row['stage'] in [0,*self.config['stages']],'durable release identity invalid')
            require(row['status'] in {'pending','baseline-blocked','dispatching','uncertain','deployed','rollback-dispatching','rollback-uncertain','healthy','rolled-back'},'unknown deployment state')
            if row['status'] in {'healthy','rolled-back'}:
                result=json.loads(row['result'],object_pairs_hook=pairs);extra='artifact_digest' if row['status']=='healthy' else 'rollback_sha'
                require(isinstance(result,dict) and set(result)=={'schema_version','operation_id','status','sha','independent_attestation',extra} and type(result['schema_version']) is int and result['schema_version']==1 and result['operation_id']==identity and result['status']==row['status'] and result['sha']==row['sha'] and result['independent_attestation'] is False,'terminal release evidence invalid')
                require(isinstance(result[extra],str) and re.fullmatch(r'[a-f0-9]{'+('64' if extra=='artifact_digest' else '40')+'}',result[extra]),'terminal release digest invalid')
                return result
            if row['status'] in {'rollback-dispatching','rollback-uncertain'}:return self.rollback(identity,row,adapter,resume=True)
            if row['status'] in {'pending','baseline-blocked'}:
                try:self.health(adapter,self.request(identity+'-baseline',row['rollback_sha'],0))
                except (ValueError,OSError):self.update(identity,status='baseline-blocked');raise
            try:
                for stage in self.config['stages']:
                    if stage<row['stage']:continue
                    request=self.request(identity,row['sha'],stage)
                    resume=row['status'] in {'dispatching','uncertain','deployed'} and stage==row['stage']
                    self.update(identity,status='dispatching',stage=stage)
                    receipt=self.receipt(request,adapter.call('lookup' if resume else 'deploy',request))
                    self.evidence(request,'receipt',receipt)
                    if row['artifact'] is not None:require(row['artifact']==receipt['artifact_digest'],'artifact changed during rollout')
                    row.update(status='deployed',stage=stage,artifact=receipt['artifact_digest']);self.update(identity,status='deployed',artifact=row['artifact'],receipt=canonical(receipt))
                    try:self.health(adapter,request)
                    except ValueError:return self.rollback(identity,row,adapter)
                result={'schema_version':1,'operation_id':identity,'status':'healthy','sha':row['sha'],'artifact_digest':row['artifact'],'independent_attestation':False}
                with self.transaction() as db:db.execute("UPDATE release_operations SET status='healthy',result=? WHERE id=?",(canonical(result),identity));db.execute('UPDATE release_binding SET known_good=? WHERE id=1',(row['sha'],))
                return result
            except (ValueError,OSError):
                with self.transaction() as db:status=db.execute('SELECT status FROM release_operations WHERE id=?',(identity,)).fetchone()[0]
                if not status.startswith('rollback-'):self.update(identity,status='uncertain')
                raise
        finally:os.close(fd)
    def rollback(self,identity,row,adapter,resume=False):
        request=self.request(identity+'-rollback',row['rollback_sha'],100);self.update(identity,status='rollback-dispatching')
        try:
            receipt=self.receipt(request,adapter.call('lookup' if resume else 'rollback',request))
            self.evidence(request,'receipt',receipt)
            self.update(identity,receipt=canonical(receipt));self.health(adapter,request)
            result={'schema_version':1,'operation_id':identity,'status':'rolled-back','sha':row['sha'],'rollback_sha':row['rollback_sha'],'independent_attestation':False};self.update(identity,status='rolled-back',result=canonical(result));return result
        except (ValueError,OSError):self.update(identity,status='rollback-uncertain');raise


def protected(path):
    path=Path(path);require(path.is_absolute() and path.resolve()==path and path.is_file() and path.stat().st_uid==os.getuid() and stat.S_IMODE(path.stat().st_mode)==0o600 and stat.S_IMODE(path.parent.stat().st_mode)==0o700 and Path(__file__).resolve().parents[2] not in path.parents,'production policy must be private and outside candidate')
    return json.loads(path.read_text(),object_pairs_hook=pairs)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--config',required=True);parser.add_argument('--policy',required=True);parser.add_argument('--db',required=True);parser.add_argument('--run-id',type=int,required=True);args=parser.parse_args()
    config=protected(args.config);validate(config);policy=protected(args.policy)
    spec=importlib.util.spec_from_file_location('receipts',Path(__file__).with_name('factory-receipts.py'));receipts=importlib.util.module_from_spec(spec);spec.loader.exec_module(receipts)
    require(policy['repository']==config['repository'],'foreign production authority')
    proof=receipts.authenticate(receipts.coordinator.GitHub(policy['repository']),policy,args.run_id)
    result=Release(args.db,config).run(proof,Adapter(config));print(canonical(result))


if __name__=='__main__':
    try:main()
    except (ValueError,KeyError,OSError,sqlite3.Error):
        print('Production release blocked; reconcile protected deployment state and adapter. Credentials withheld.',file=__import__('sys').stderr);raise SystemExit(2)
