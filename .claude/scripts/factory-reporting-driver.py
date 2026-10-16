#!/usr/bin/env python3
"""Finite serial reporting CLI continuation; protected state remains resume authority."""
import argparse
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import time
from urllib.parse import quote


def load(name, path):
    spec=importlib.util.spec_from_file_location(name,path)
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value


def require(condition, reason):
    if not condition:raise ValueError(reason)


ROOT=Path(__file__).resolve().parents[2]
PROCESS=load('reporting_driver_process',ROOT/'.claude/scripts/factory-bounded-process.py')


def source_pin():
    env={key:os.environ[key] for key in ('PATH','HOME') if key in os.environ}
    env.update(GIT_CONFIG_GLOBAL='/dev/null',GIT_CONFIG_SYSTEM='/dev/null')
    def git(*args):
        result=PROCESS.run(['git','-c','core.fsmonitor=false','-C',str(ROOT),*args],env=env,cwd=ROOT,timeout=5,limit=8192,aggregate_limit=8192)
        require(result.returncode==0,'reporting source checkout unavailable')
        return result.stdout.decode().strip()
    head=git('rev-parse','HEAD')
    require(re.fullmatch('[0-9a-f]{40}',head) and not git('status','--porcelain','--untracked-files=no','--','.claude/scripts'), 'reporting source checkout changed')
    if os.environ.get('GITHUB_SHA') is not None:require(os.environ['GITHUB_SHA']==head,'reporting source SHA differs')
    return head


def drive(config_path, *, max_seconds=720, max_invocations=256):
    require(type(max_seconds) is int and 1<=max_seconds<=720 and type(max_invocations) is int and 1<=max_invocations<=512,'reporting driver bounds invalid')
    flag=os.environ.get('FACTORY_REPORTING_APP_WRITER_ENABLED','false')
    require(flag in ('true','false'),'reporting writer flag invalid')
    path=Path(config_path)
    require(path.is_absolute() and path.resolve()==path and not path.is_symlink() and path.is_file(),'reporting driver config path invalid')
    started=time.monotonic();deadline=started+max_seconds-min(30,max_seconds/3)
    config_raw=path.read_bytes();require(0<len(config_raw)<=1048576,'reporting driver config size invalid')
    config_hash=hashlib.sha256(config_raw).digest()
    pinned=source_pin();observer=None;previous=None;unchanged=0;invocations=0
    if flag=='true':
        transport=load('reporting_driver_transport',ROOT/'.claude/scripts/factory-reporting-transport.py')
        config=transport.state.digest.coordinator.contract.load(path)
        observer=transport.create_api(os.environ)
        require(config['repository']==config['state_repository']==observer.repo,'reporting driver repository differs')
        branch=config['state_branch'];require(type(branch) is str and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._/-]*',branch) and '..' not in branch and not branch.endswith('/'),'reporting driver state branch invalid')
    def summary(status,reason=None,phase=None):
        result={'status':status,'invocations':invocations,'elapsed_seconds':round(time.monotonic()-started,3),
                'source_sha':pinned,'child_api_counters_available':False,'retry_policy':'later-job',
                'observer_calls':0 if observer is None else observer.budget.calls,
                'observer_bytes':0 if observer is None else observer.budget.bytes}
        if reason is not None:result['reason']=reason
        if phase is not None:result['phase']=phase
        return result
    while invocations<max_invocations:
        if time.monotonic()>=deadline:return summary('incomplete','job-deadline')
        require(source_pin()==pinned,'reporting source SHA changed')
        require(not path.is_symlink() and hashlib.sha256(path.read_bytes()).digest()==config_hash,'reporting driver config changed')
        remaining=deadline-time.monotonic()
        if remaining<=0:return summary('incomplete','job-deadline')
        try:
            child=PROCESS.run([sys.executable,'-I',str(ROOT/'.claude/scripts/factory-git-state.py'),'--config',str(path)],
                env=dict(os.environ),cwd=ROOT,timeout=min(300,remaining),max_timeout=300,limit=1048576,aggregate_limit=1048576)
        except ValueError as error:
            if str(error)=='trusted subprocess timeout':return summary('incomplete','child-timeout')
            raise
        invocations+=1
        if flag=='false':
            # OFF remains one legacy CLI execution with its original output.
            sys.stdout.buffer.write(child.stdout);sys.stdout.buffer.flush();sys.stderr.buffer.write(child.stderr);sys.stderr.buffer.flush();return child.returncode
        if child.returncode!=0:return summary('blocked','child-failed')
        try:result=json.loads(child.stdout)
        except (ValueError,UnicodeError):raise ValueError('reporting child result invalid') from None
        require(type(result) is dict and result.get('status') in ('incomplete','delivered','not-due'),'reporting child status invalid')
        phase=result.get('phase')
        require(phase is None or type(phase) is str and re.fullmatch('[a-z-]{1,64}',phase),'reporting child phase invalid')
        if result['status']!='incomplete':return summary(result['status'],phase=phase)
        # Observer uses a separate retained whole-job budget. Child counters are
        # never reset in-process or fabricated; each CLI invocation owns its own.
        if deadline-time.monotonic()<60:return summary('incomplete','job-deadline',phase)
        ref=observer.request('repos/'+observer.repo+'/git/ref/heads/'+quote(branch,safe=''))
        require(type(ref) is dict and ref.get('ref')=='refs/heads/'+branch and type(ref.get('object')) is dict
                and ref['object'].get('type')=='commit' and type(ref['object'].get('sha')) is str
                and re.fullmatch('[0-9a-f]{40}',ref['object']['sha']),'reporting observer identity invalid')
        head=ref['object']['sha'];unchanged=unchanged+1 if head==previous else 0;previous=head
        if unchanged>=3:return summary('incomplete','no-state-progress',phase)
    return summary('incomplete','job-invocation-limit')


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--config',type=Path,required=True)
    parser.add_argument('--max-seconds',type=int,default=720);parser.add_argument('--max-invocations',type=int,default=256)
    args=parser.parse_args();result=drive(args.config,max_seconds=args.max_seconds,max_invocations=args.max_invocations)
    if type(result) is int:return result
    print(json.dumps(result,sort_keys=True));return int(result['status']=='blocked')


if __name__=='__main__':
    try:sys.exit(main())
    except (ValueError,KeyError,TypeError,OSError):
        print('{"status":"blocked","reason":"reporting-driver-stopped","retry_policy":"later-job"}',file=sys.stderr);sys.exit(1)
