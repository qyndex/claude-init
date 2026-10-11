#!/usr/bin/env python3
"""Trusted offline Linux worker adapter; daemon absence gates replay."""
import argparse
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import subprocess
import stat
import sys
import time
import tempfile


bounded_spec=importlib.util.spec_from_file_location('bounded_process',Path(__file__).with_name('factory-bounded-process.py'))
bounded=importlib.util.module_from_spec(bounded_spec);bounded_spec.loader.exec_module(bounded)

def require(condition, message):
    if not condition:raise ValueError(message)


def pairs(items):
    result={}
    for key,value in items:
        require(key not in result,'duplicate container configuration field')
        result[key]=value
    return result


def validate(config):
    require(isinstance(config,dict) and set(config)=={'kind','binary','sha256','image','repository','memory_mb','cpus','pids_limit'},'container adapter fields invalid')
    require(config['kind']=='docker-offline','unsupported container adapter')
    require(isinstance(config['binary'],str) and Path(config['binary']).is_absolute() and isinstance(config['sha256'],str) and re.fullmatch(r'[a-f0-9]{64}',config['sha256']),'Docker executable pin required')
    require(isinstance(config['image'],str) and re.fullmatch(r'sha256:[a-f0-9]{64}',config['image']),'locally present immutable image ID required')
    require(isinstance(config['repository'],str) and re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',config['repository']),'container repository invalid')
    require(type(config['memory_mb']) is int and 64<=config['memory_mb']<=8192 and type(config['pids_limit']) is int and 8<=config['pids_limit']<=256,'container resource bounds invalid')
    require(type(config['cpus']) in {int,float} and math.isfinite(config['cpus']) and .1<=config['cpus']<=8,'container CPU bound invalid')
    return config


class Container:
    def __init__(self,config,store,task,owner,token,directory,candidate,command):
        self.config=validate(config);self.store=store;self.task=task;self.owner=owner;self.token=token;self.directory=Path(directory);self.candidate=Path(candidate);self.registered=False;self.create_acknowledged=False;self.observed_created=False
        require(sys.platform=='linux' and os.getuid()>0,'offline container adapter requires nonroot Linux controller')
        binary=Path(config['binary']);require(binary.resolve()==binary and binary.is_file() and os.access(binary,os.X_OK) and hashlib.sha256(binary.read_bytes()).hexdigest()==config['sha256'],'Docker executable pin changed')
        require(self.candidate.resolve()==self.candidate and self.candidate.is_dir() and self.candidate!=Path('/') and self.candidate!=Path.home() and not any(char in str(self.candidate) for char in ',\r\n'),'candidate mount path unsafe')
        private=Path(store.path).resolve().parent
        require(private.stat().st_uid==os.getuid() and stat.S_IMODE(private.stat().st_mode)==0o700 and stat.S_IMODE(Path(store.path).stat().st_mode)==0o600,'container runtime state must be private')
        require(self.candidate!=private and self.candidate not in private.parents and self.candidate!=self.directory and self.candidate not in self.directory.parents,'container cannot mount private runtime or attempt state')
        require(isinstance(command,list) and bool(command) and all(isinstance(arg,str) and '\0' not in arg for arg in command) and Path(command[0]).is_absolute(),'absolute container foreground argv required')
        count=0
        for current,directories,files in os.walk(self.candidate,followlinks=False):
            for name in [*directories,*files]:
                count+=1;require(count<=100000,'candidate mount inventory bound exceeded')
                info=(Path(current)/name).lstat()
                require(stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode) or (stat.S_ISREG(info.st_mode) and info.st_nlink==1),'candidate special file/hardlink can expose host resources')
        self.command=command;self.namespace=self.directory.name;self.name='factory-'+hashlib.sha256(self.namespace.encode()).hexdigest()[:32]
        self.identity={'repository':config['repository'],'namespace':self.namespace,'name':self.name,'image':config['image']};store.worker_effect_identity(self.identity)
        self.effect_id=self.name;self.labels={'factory.repository':config['repository'],'factory.task':task,'factory.fence':str(token),'factory.namespace':self.namespace}
        self.client_home=tempfile.TemporaryDirectory(prefix='factory-docker-client-');self.environment={'PATH':os.defpath,'HOME':self.client_home.name,'LC_ALL':'C'}
        self.prefix=[config['binary'],'--config',self.client_home.name,'--host','unix:///var/run/docker.sock']

    def call(self,args):
        result=bounded.run([*self.prefix,*args],env=self.environment,cwd=self.client_home.name,timeout=12)
        require(result.returncode==0,'Docker acknowledgement unavailable')
        return result.stdout.decode()

    def create(self):
        image=json.loads(self.call(['image','inspect',self.config['image']]))
        require(isinstance(image,list) and len(image)==1 and image[0]['Id']==self.config['image'] and not image[0]['Config'].get('Volumes'),'image identity/implicit volumes differ')
        self.store.register_worker_effect(self.task,self.owner,self.token,self.effect_id,self.identity);self.registered=True
        allowed={'PATH','HOME','LANG','LC_ALL','TZ','TMPDIR'}
        require(all(isinstance(value,str) and value.split('=',1)[0] in allowed for value in (image[0]['Config'].get('Env') or [])),'image embeds undeclared environment')
        args=['container','create','--name',self.name,'--read-only','--no-healthcheck','--log-driver','none','--cap-drop','ALL','--security-opt','no-new-privileges','--network','none','--init','--restart','no','--pids-limit',str(self.config['pids_limit']),'--memory',str(self.config['memory_mb'])+'m','--memory-swap',str(self.config['memory_mb'])+'m','--cpus',str(self.config['cpus']),'--user',f'{os.getuid()}:{os.getgid()}','--ipc','private','--tmpfs','/tmp:rw,noexec,nosuid,nodev,size=64m,mode=1777','--env','HOME=/tmp','--env','TMPDIR=/tmp','--workdir','/workspace','--mount',f'type=bind,src={self.candidate},dst=/workspace','--entrypoint',self.command[0]]
        for key,value in self.labels.items():args+=['--label',key+'='+value]
        args+=[self.config['image'],*self.command[1:]]
        self.call(args);self.create_acknowledged=True;self.inspect_owned()
        return [*self.prefix,'container','start','--attach',self.name]

    def inspect_owned(self):
        values=json.loads(self.call(['container','inspect',self.name]));require(isinstance(values,list) and len(values)==1,'container identity ambiguous')
        value=values[0];require(isinstance(value,dict) and isinstance(value.get('Config'),dict) and isinstance(value['Config'].get('Labels'),dict) and isinstance(value.get('State'),dict),'container inspection fields invalid')
        require(value['Name']=='/'+self.name and value['Image']==self.identity['image'] and all(value['Config']['Labels'].get(key)==expected for key,expected in self.labels.items()),'foreign daemon resource; cleanup blocked')
        require(isinstance(value['Id'],str) and re.fullmatch(r'[a-f0-9]{64}',value['Id']),'container ID invalid')
        require(value['State']['Status'] in {'created','running','paused','exited','dead'},'daemon creation/removal still uncertain')
        self.store.confirm_worker_effect_presence(self.task,self.owner,self.token,{'schema_version':1,'adapter':'docker-offline','effect_id':self.effect_id,'identity':self.identity,'observed_present':True,'container_id':value['Id']})
        self.observed_created=True
        return value['Id']

    def present(self):
        result=self.call(['container','ls','--all','--no-trunc','--filter','name=^/'+self.name+'$','--format','{{json .}}'])
        rows=[json.loads(line) for line in result.splitlines() if line];require(len(rows)<=1 and all(row.get('Names')==self.name for row in rows),'container listing identity differs')
        return bool(rows)

    def cleanup(self):
        if not self.registered:return
        if self.present():self.call(['container','rm','--force',self.inspect_owned()])
        require(self.create_acknowledged or self.observed_created,'unacknowledged create absence is not conclusive')
        require(not self.present(),'daemon worker survived cleanup')
        self.store.confirm_worker_effect_cleanup(self.task,self.owner,self.token,{'schema_version':1,'adapter':'docker-offline','effect_id':self.effect_id,'identity':self.identity,'observed_absent':True})

    @classmethod
    def for_cleanup(cls,config,store,effect):
        value=cls.__new__(cls);value.config=validate(config);value.store=store
        require(sys.platform=='linux' and os.getuid()>0,'offline cleanup requires nonroot Linux controller')
        binary=Path(config['binary']);require(binary.resolve()==binary and binary.is_file() and os.access(binary,os.X_OK) and hashlib.sha256(binary.read_bytes()).hexdigest()==config['sha256'],'Docker executable pin changed')
        value.identity=json.loads(effect['identity']);store.worker_effect_identity(value.identity)
        require(value.identity['repository']==config['repository'] and effect['id']==value.identity['name'],'foreign adapter effect identity')
        value.task=effect['task'];value.owner=effect['owner'];value.token=effect['fence'];value.name=value.identity['name'];value.namespace=value.identity['namespace'];value.effect_id=effect['id']
        require(value.namespace.startswith(f'{value.task}-{value.token}-'),'external effect task/fence differs')
        value.labels={'factory.repository':config['repository'],'factory.task':value.task,'factory.fence':str(value.token),'factory.namespace':value.namespace}
        value.registered=True;value.create_acknowledged=bool(effect.get('presence'));value.observed_created=False
        value.client_home=tempfile.TemporaryDirectory(prefix='factory-docker-client-');value.environment={'PATH':os.defpath,'HOME':value.client_home.name,'LC_ALL':'C'}
        value.prefix=[config['binary'],'--config',value.client_home.name,'--host','unix:///var/run/docker.sock']
        return value

    def close(self):
        self.client_home.cleanup()


def main():
    parser=argparse.ArgumentParser(description='Reconcile stale offline worker effects; never dispatch or revive tasks')
    parser.add_argument('--config',required=True);parser.add_argument('--db',required=True);parser.add_argument('--task',required=True);args=parser.parse_args()
    for value in (args.config,args.db):
        path=Path(value)
        require(path.is_absolute() and path.resolve()==path and path.is_file() and path.stat().st_uid==os.getuid() and stat.S_IMODE(path.stat().st_mode)==0o600 and path.parent.stat().st_uid==os.getuid() and stat.S_IMODE(path.parent.stat().st_mode)==0o700,'cleanup configuration/state must be private owned canonical paths')
    config=validate(json.loads(Path(args.config).read_text(),object_pairs_hook=pairs))
    module=importlib.util.spec_from_file_location('runtime',Path(__file__).with_name('factory-runtime.py'));runtime=importlib.util.module_from_spec(module);module.loader.exec_module(runtime)
    store=runtime.Store(args.db);row=store.get(args.task)
    require(row['expires'] is None or row['expires']<=time.time() or row['state'] in {'blocked','cancelled'},'current worker lease still active')
    cleaned=0
    for effect in store.worker_effects(args.task):
        if effect['status']=='clean':continue
        adapter=Container.for_cleanup(config,store,effect)
        try:adapter.cleanup();cleaned+=1
        finally:adapter.close()
    print(json.dumps({'task':args.task,'cleaned':cleaned,'engineering_verified':False}))


if __name__=='__main__':
    try:main()
    except (ValueError,KeyError,TypeError,OSError,subprocess.SubprocessError):
        print('Container cleanup blocked; preserve uncertain intent and inspect trusted daemon/configuration.',file=sys.stderr);sys.exit(2)
