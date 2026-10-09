#!/usr/bin/env python3
"""Own a foreground worker for its lifetime; exit zero means ready for verification."""
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
import uuid

spec = importlib.util.spec_from_file_location('runtime', Path(__file__).with_name('factory-runtime.py'))
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


def group_exists(pgid):
    result = subprocess.run(['ps', '-axo', 'pgid='], capture_output=True, text=True, check=True)
    return str(pgid) in result.stdout.split()


def terminate(worker):
    # macOS may return EPERM rather than ESRCH for a vanished process group.
    if not group_exists(worker.pid):
        worker.wait(timeout=5)
        return
    try:
        os.killpg(worker.pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        if group_exists(worker.pid):
            raise
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline and group_exists(worker.pid):
        worker.poll()
        time.sleep(.05)
    if group_exists(worker.pid):
        try:
            os.killpg(worker.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            if group_exists(worker.pid):
                raise
    worker.wait(timeout=5)


def supervise(db, task, command, cwd, attempts, timeout=1800, lease=30):
    lock = Path(db).resolve().parent / ("worker-" + hashlib.sha256(task.encode()).hexdigest() + ".lock")
    lock.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(lock, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise runtime.Blocked("worker still holds task lock") from error
        return supervised(db, task, command, cwd, attempts, timeout, lease, fd)
    finally:
        os.close(fd)


def supervised(db, task, command, cwd, attempts, timeout, lease, lock_fd):
    if not command or '--bg' in command or '--background' in command:
        raise ValueError('foreground command required')
    if not 1 <= timeout <= 21600 or not 3 <= lease <= 3600:
        raise ValueError('invalid supervision bounds')
    owner = 'supervisor:' + uuid.uuid4().hex
    store = runtime.Store(db)
    token = store.claim(task, owner, lease)
    directory = Path(attempts) / f'{task}-{token}-{uuid.uuid4().hex}'
    directory.mkdir(parents=True, mode=0o700)
    stopped = []
    previous = {}
    worker = None
    reason = 'startup-failure'
    code = 1
    started = time.monotonic()
    try:
        for sig in (signal.SIGTERM, signal.SIGINT):
            previous[sig] = signal.signal(sig, lambda signum, frame: stopped.append(signum))
        store.transition(task, owner, token, 'implementing')
        env = dict(os.environ, FACTORY_RUN_DIR=str(directory.resolve()), TMPDIR=str(directory.resolve()))
        with (directory / 'worker.log').open('wb') as log:
            worker = subprocess.Popen(command, cwd=cwd, env=env, stdout=log,
                                      stderr=subprocess.STDOUT, start_new_session=True, pass_fds=(lock_fd,))
            next_heartbeat = time.monotonic()
            while True:
                if stopped:
                    reason = 'cancelled'; break
                if time.monotonic() - started >= timeout:
                    reason = 'timeout'; break
                if time.monotonic() >= next_heartbeat:
                    try:
                        store.heartbeat(task, owner, token, lease)
                    except runtime.Blocked:
                        reason = 'lease-lost'; break
                    next_heartbeat = time.monotonic() + lease / 3
                result = worker.poll()
                if result is not None:
                    code = 0 if result == 0 else 1
                    reason = 'worker-success' if result == 0 else 'worker-failure'
                    break
                time.sleep(.05)
        terminate(worker)
        try:
            store.transition(task, owner, token, 'verifying' if code == 0 else 'blocked')
        except runtime.Blocked:
            code = 1; reason = 'lease-lost'
        return code
    except Exception:
        try:
            store.transition(task, owner, token, 'blocked')
        except runtime.Blocked:
            reason = 'lease-lost'
        raise
    finally:
        if worker is not None:
            terminate(worker)
        for sig, handler in previous.items():
            signal.signal(sig, handler)
        (directory / 'outcome.json').write_text(json.dumps({
            'task': task, 'owner': owner, 'fence': token, 'argv': command,
            'reason': reason, 'exit_code': code, 'engineering_verified': False,
            'elapsed_seconds': time.monotonic() - started,
        }, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--db', required=True)
    parser.add_argument('--task', required=True)
    parser.add_argument('--cwd', required=True)
    parser.add_argument('--attempts', required=True)
    parser.add_argument('--timeout', type=float, default=1800)
    parser.add_argument('--lease', type=float, default=30)
    parser.add_argument('--detach', action='store_true')
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if args.detach:
        if not command or '--bg' in command or '--background' in command:
            parser.error('foreground command required')
        logs = Path(args.attempts); logs.mkdir(parents=True, exist_ok=True)
        with (logs / ('launcher-' + uuid.uuid4().hex + '.log')).open('wb') as log:
            argv = list(sys.argv[1:])
            argv.remove('--detach')
            child = subprocess.Popen([sys.executable, __file__, *argv], stdin=subprocess.DEVNULL,
                                     stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        print(json.dumps({'supervisor_pid': child.pid, 'claimed': False}))
        return 0
    return supervise(args.db, args.task, command, args.cwd, args.attempts, args.timeout, args.lease)


if __name__ == '__main__':
    sys.exit(main())
