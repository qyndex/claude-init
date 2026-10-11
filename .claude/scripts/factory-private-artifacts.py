#!/usr/bin/env python3
"""Sanitized runtime metrics and guarded terminal-attempt retention."""
import argparse
import fcntl
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import shutil
import sqlite3
import stat
import time


def require(condition,message):
    if not condition:raise ValueError(message)


def pairs(items):
    result={}
    for key,value in items:
        require(key not in result,'duplicate artifact policy field');result[key]=value
    return result


def private(path,directory=False):
    path=Path(path)
    require(path.is_absolute() and path.resolve()==path and not path.is_symlink() and path.stat().st_uid==os.getuid(),'private canonical owned path required')
    require(Path(__file__).resolve().parents[2] not in path.parents,'private artifact paths cannot live in the candidate checkout')
    require((path.is_dir() if directory else path.is_file()) and stat.S_IMODE(path.stat().st_mode)==(0o700 if directory else 0o600),'private path mode invalid')
    return path


def namespace(db,repository):
    names={row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    bindings=[]
    for table in ('runtime_route_repository','worker_effect_repository'):
        if table in names:bindings.extend(row[0] for row in db.execute(f'SELECT repository FROM {table} WHERE id=1'))
    require(bindings and set(bindings)=={repository},'unbound/foreign private runtime namespace')


def metrics(store,repository):
    with store.transaction() as db:
        namespace(db,repository)
        counts={row[0]:row[1] for row in db.execute('SELECT state,count(*) FROM tasks GROUP BY state')}
        require(set(counts)<={'queued','claimed','implementing','verifying','repairing','merge-ready','merging','merged','blocked','cancelled'},'unknown runtime metric state')
        unresolved=db.execute("SELECT count(*) FROM worker_effects WHERE status!='clean'").fetchone()[0]
    return {'schema_version':1,'repository':repository,'runtime_states':counts,'unresolved_worker_effects':unresolved,'engineering_verified':False}


def safe_tree(directory):
    count=0;stack=[os.scandir(directory)]
    try:
        while stack:
            try:entry=next(stack[-1])
            except StopIteration:stack.pop().close();continue
            count+=1
            if count>10000:return False
            value=entry.stat(follow_symlinks=False)
            if value.st_uid!=os.getuid():return False
            if stat.S_ISDIR(value.st_mode):
                if len(stack)>=128:return False
                stack.append(os.scandir(entry.path))
            elif not (stat.S_ISREG(value.st_mode) and value.st_nlink==1):return False
        return True
    finally:
        for stream in stack:stream.close()


def retain(store,repository,attempts,days,*,apply=False,now=None):
    attempts=private(attempts,True);database=private(store.path);private(database.parent,True)
    require(attempts.parent==database.parent and type(days) is int and 1<=days<=365,'retention bounds/storage differ')
    now=time.time() if now is None else now;require(type(now) in {int,float} and math.isfinite(now),'retention clock invalid')
    with store.transaction() as db:namespace(db,repository)
    entries=[]
    for entry in attempts.iterdir():
        require(len(entries)<1000,'retention inventory bound exceeded');entries.append(entry)
    eligible=deleted=0
    for directory in entries:
        match=re.fullmatch(r'(T-[1-9][0-9]*)-([1-9][0-9]*)-[a-f0-9]{32}',directory.name)
        if not match or directory.is_symlink() or not directory.is_dir():continue
        if directory.stat().st_uid!=os.getuid() or stat.S_IMODE(directory.stat().st_mode)!=0o700:continue
        task=match[1];fence=int(match[2]);lock=database.parent/('worker-'+hashlib.sha256(task.encode()).hexdigest()+'.lock')
        if lock.is_symlink() or (lock.exists() and (not lock.is_file() or lock.stat().st_uid!=os.getuid())):continue
        descriptor=os.open(lock,os.O_CREAT|os.O_RDWR|getattr(os,'O_NOFOLLOW',0),0o600)
        try:
            try:fcntl.flock(descriptor,fcntl.LOCK_EX|fcntl.LOCK_NB)
            except BlockingIOError:continue
            with store.transaction() as db:
                namespace(db,repository);row=db.execute('SELECT state,fence FROM tasks WHERE id=?',(task,)).fetchone()
                if row is None or row[0] not in {'merged','blocked','cancelled'} or row[1]<fence:continue
                if db.execute("SELECT 1 FROM worker_effects WHERE task=? AND status!='clean'",(task,)).fetchone():continue
                if db.execute("SELECT 1 FROM outbox WHERE task=? AND status!='confirmed'",(task,)).fetchone():continue
                outcome=directory/'outcome.json';guardian=directory/'guardian.json'
                if any(not p.is_file() or p.is_symlink() or p.stat().st_size>64000 for p in (outcome,guardian)):continue
                if outcome.stat().st_mtime>now-days*86400:continue
                try:result=json.loads(outcome.read_text());cleanup=json.loads(guardian.read_text())
                except (ValueError,UnicodeError):continue
                if not isinstance(result,dict) or result.get('task')!=task or type(result.get('fence')) is not int or result['fence']!=fence:continue
                if not isinstance(cleanup,dict) or cleanup.get('worker_cleanup_confirmed') is not True:continue
                if not safe_tree(directory):continue
                eligible+=1
                if apply:shutil.rmtree(directory);deleted+=1
        finally:os.close(descriptor)
    return {'schema_version':1,'eligible_attempts':eligible,'deleted_attempts':deleted,'dry_run':not apply,'engineering_verified':False}


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--config',required=True);parser.add_argument('--db',required=True);parser.add_argument('--attempts',required=True);parser.add_argument('--apply',action='store_true');parser.add_argument('operation',choices=['metrics','retain']);args=parser.parse_args()
    path=private(args.config);private(path.parent,True);database=private(args.db);private(database.parent,True)
    config=json.loads(path.read_text(),object_pairs_hook=pairs);require(isinstance(config,dict) and set(config)=={'repository','retention_days'} and isinstance(config['repository'],str) and re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',config['repository']),'artifact policy invalid')
    require(type(config['retention_days']) is int and 1<=config['retention_days']<=365,'retention policy bound invalid')
    require(not args.apply or args.operation=='retain','apply requires retention operation')
    spec=importlib.util.spec_from_file_location('runtime',Path(__file__).with_name('factory-runtime.py'));runtime=importlib.util.module_from_spec(spec);spec.loader.exec_module(runtime);store=runtime.Store(database)
    result=metrics(store,config['repository']) if args.operation=='metrics' else retain(store,config['repository'],args.attempts,config['retention_days'],apply=args.apply)
    print(json.dumps(result,sort_keys=True))


if __name__=='__main__':
    try:main()
    except (ValueError,KeyError,OSError,sqlite3.Error):
        print('Private artifact operation blocked; preserve state and reconcile protected configuration. Raw data withheld.',file=__import__('sys').stderr);raise SystemExit(2)
