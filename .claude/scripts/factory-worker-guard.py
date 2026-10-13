#!/usr/bin/env python3
"""Terminate a foreground worker if its supervisor's liveness pipe closes."""
import argparse
import importlib.util
import json
import hashlib
import pwd
import re
import sqlite3
import stat
import types
import os
from pathlib import Path
import select
import signal
import subprocess
import sys

def require(condition,message):
    if not condition:raise ValueError(message)


def decode(raw):
    def pairs(items):
        result={}
        for key,value in items:require(key not in result,'duplicate guardian control');result[key]=value
        return result
    return json.loads(raw,object_pairs_hook=pairs)


def start_bytes(path,private_file=False):
    path=Path(path)
    require(path.is_absolute() and path.resolve()==path and not path.is_symlink(),'start control path not canonical')
    if private_file:
        require(path.parent.stat().st_uid==os.getuid() and stat.S_IMODE(path.parent.stat().st_mode)==0o700,'start control parent not private')
    fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
    try:
        info=os.fstat(fd)
        require(stat.S_ISREG(info.st_mode) and info.st_nlink==1 and info.st_size<=8000000,'start control file invalid')
        if private_file:require(info.st_uid==os.getuid() and stat.S_IMODE(info.st_mode)==0o600,'start control file not private')
        with os.fdopen(fd,'rb',closefd=False) as stream:raw=stream.read(8000001)
        require(len(raw)<=8000000,'start control bytes exceeded');return raw
    finally:os.close(fd)


def start_installation(root,*,database=None):
    """Stdlib-only OS registry read; no candidate environment/config selection."""
    home=Path(pwd.getpwuid(os.getuid()).pw_dir)
    require(home.is_absolute() and home.resolve()==home and home.is_dir(),'start OS home not canonical')
    directory=home/'.local/state/factory-required-intake';latch=home/'.factory-intake-required'
    if not directory.exists() and not latch.exists():return None
    require(directory.resolve()==directory and directory.is_dir() and directory.stat().st_uid==os.getuid()
            and stat.S_IMODE(directory.stat().st_mode)==0o700 and latch.exists(),'start registry missing or unsafe')
    latched=decode(start_bytes(latch));info=latch.stat()
    require(info.st_uid==os.getuid() and stat.S_IMODE(info.st_mode)==0o600,'start latch not private')
    records=decode(start_bytes(directory/'registry.json',True))
    require(isinstance(latched,dict) and set(latched)=={'schema_version','bindings'} and type(latched['schema_version']) is int
            and latched['schema_version']==1 and isinstance(latched['bindings'],dict)
            and isinstance(records,dict) and set(records)=={'schema_version','roots'} and type(records['schema_version']) is int
            and records['schema_version']==1 and isinstance(records['roots'],dict)
            and set(records['roots'])==set(latched['bindings']) and 0<len(records['roots'])<=1000,'start registry schema differs')
    fields={'repository','authority_root','candidate_root','contract','database','profile','policy','contract_sha256'}
    matched=[]
    for key,entry in records['roots'].items():
        require(isinstance(entry,dict) and set(entry)==fields and entry['authority_root']==key
                and isinstance(entry['repository'],str) and re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',entry['repository'])
                and isinstance(entry['contract_sha256'],str) and re.fullmatch(r'[a-f0-9]{64}',entry['contract_sha256'])
                and latched['bindings'][key]==entry['contract_sha256'],'start registry entry differs')
        for name in fields-{'repository','contract_sha256'}:
            require(isinstance(entry[name],str) and Path(entry[name]).is_absolute() and Path(entry[name]).resolve()==Path(entry[name]),'start registry path malformed')
        if str(root) in {entry['candidate_root'],entry['authority_root']} or (database is not None and str(database)==entry['database']):matched.append(entry)
    require(len(matched)<=1,'start registry selection ambiguous')
    return matched[0] if matched else None


class LazySupervisor:
    def __init__(self):self.module=None
    def __getattr__(self,name):
        if self.module is None:
            spec=importlib.util.spec_from_file_location('supervisor',Path(__file__).with_name('factory-supervisor.py'))
            self.module=importlib.util.module_from_spec(spec);spec.loader.exec_module(self.module)
        return getattr(self.module,name)

supervisor=LazySupervisor()


def protected_intake_main(argv):
    parser=argparse.ArgumentParser();parser.add_argument('--intake-descriptor',required=True);parser.add_argument('--watch-fd',required=True,type=int)
    args=parser.parse_args(argv)
    try:
        document=decode(start_bytes(args.intake_descriptor,True));entry=start_installation(Path(document['authority_root']))
        require(entry is not None and entry['contract']==document['contract'] and entry['contract_sha256']==document['contract_sha256'],'guardian required installation differs')
        contract=decode(start_bytes(entry['contract'],True))
        canonical=lambda value:json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False,allow_nan=False)
        require(hashlib.sha256(canonical(contract).encode()).hexdigest()==entry['contract_sha256'],'guardian installed contract changed')
        path=str(Path(__file__).with_name('factory-intake-worker.py').resolve());require(path in contract['trusted_files'],'guardian worker bootstrap not pinned')
        raw=start_bytes(path);require(hashlib.sha256(raw).hexdigest()==contract['trusted_files'][path],'guardian worker bootstrap changed')
        worker=types.ModuleType('protected_guardian_worker');worker.__file__=path
        exec(compile(raw,path,'exec'),worker.__dict__)
        return worker.guarded_native(args.intake_descriptor,args.watch_fd)
    except (ValueError,OSError,KeyError,TypeError,sqlite3.Error):
        print('Protected native guardian blocked.',file=sys.stderr);return 2


def legacy_boundary(database):
    path=Path(database)
    require(path.is_absolute() and path.resolve()==path and not path.is_symlink(),'guardian database path not canonical')
    require(start_installation(Path.cwd().resolve(),database=path) is None,'mandatory guardian descriptor omitted')
    if path.exists():
        with sqlite3.connect(path.as_uri()+'?mode=ro',uri=True) as db:
            names={row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        require(not {'intake_identity','runtime_intake_required'}&names,'mandatory guardian descriptor omitted')


def main():
    if '--intake-descriptor' in sys.argv[1:]:return protected_intake_main(sys.argv[1:])
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--watch-fd', type=int, required=True)
    parser.add_argument('--inherit-fds', required=True)
    parser.add_argument('--db', required=True)
    parser.add_argument('--task', required=True)
    parser.add_argument('--owner', required=True)
    parser.add_argument('--token', type=int, required=True)
    parser.add_argument('--outcome', type=Path, required=True)
    parser.add_argument('--execution')
    parser.add_argument('--output-limit',type=int,default=1000000)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    try:legacy_boundary(args.db)
    except (ValueError,OSError,sqlite3.Error):
        print('Required guardian entry blocked.',file=sys.stderr);return 2
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    inherited = json.loads(args.inherit_fds)
    if not command or any(type(fd) is not int or fd < 0 or fd == args.watch_fd for fd in inherited):
        parser.error('invalid foreground worker/descriptors')
    if not 1024<=args.output_limit<=8000000:
        parser.error('worker output bound invalid')
    stopped = []
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, lambda signum, frame: stopped.append(signum))
    worker = None
    container = None
    reason = 'startup-failure'
    code = 1
    orphaned = False
    clean = False
    try:
        environment = None
        directory = None
        if args.execution:
            module = importlib.util.spec_from_file_location('container_adapter', Path(__file__).with_name('factory-container.py'))
            adapter = importlib.util.module_from_spec(module); module.loader.exec_module(adapter)
            container = adapter.Container(json.loads(args.execution), supervisor.runtime.Store(args.db), args.task, args.owner, args.token, args.outcome.parent, Path.cwd().resolve(), command)
            command = container.create(); environment = container.environment; directory = container.client_home.name
        worker = subprocess.Popen(command, start_new_session=True, pass_fds=tuple(inherited), env=environment, cwd=directory, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        os.set_blocking(worker.stdout.fileno(),False)
        captured=0;output_open=True
        while True:
            descriptors=[args.watch_fd]+([worker.stdout.fileno()] if output_open else [])
            readable, _, _ = select.select(descriptors, [], [], .05)
            if args.watch_fd in readable and os.read(args.watch_fd, 1) == b'':
                orphaned = True; reason = 'supervisor-lost'; break
            if stopped:
                reason = 'guardian-stopped'; break
            if output_open and worker.stdout.fileno() in readable:
                data=os.read(worker.stdout.fileno(),65536)
                if not data:output_open=False
                else:
                    remaining=args.output_limit-captured
                    sys.stdout.buffer.write(data[:remaining]);sys.stdout.buffer.flush()
                    captured+=min(remaining,len(data))
                    if len(data)>remaining:
                        reason='output-limit';code=1;break
            result = worker.poll()
            if result is not None and not output_open:
                code = result if result >= 0 else 128 - result
                reason = 'worker-success' if code == 0 else 'worker-failure'
                break
        return code
    finally:
        try:
            if worker is not None:
                supervisor.terminate(worker, grace=.5)
            if worker is not None:
                worker.stdout.close()
            if container is not None:
                container.cleanup()
            clean = True
        finally:
            if container is not None:
                container.close()
            if orphaned:
                # Unknown cleanup never permits replay, even if the lease expired.
                supervisor.runtime.Store(args.db).recover_worker(args.task, args.owner, args.token, requeue=clean)
            args.outcome.write_text(json.dumps({'reason': reason, 'exit_code': code,
                                               'worker_cleanup_confirmed': clean,
                                               'external_cleanup_confirmed': clean if args.execution else None,
                                               'engineering_verified': False}, indent=2) + '\n')
            os.close(args.watch_fd)


if __name__ == '__main__':
    sys.exit(main())
