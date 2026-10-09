#!/usr/bin/env python3
"""Serialize cooperating writers, including nested scripts, on one OS lock."""
import argparse
import fcntl
import os
from pathlib import Path
import subprocess
import sys
import time


def run(lock, command, timeout=30):
    lock = Path(lock).resolve()
    lock.parent.mkdir(parents=True, exist_ok=True)
    fd = None
    value = os.environ.get('FACTORY_STATE_LOCK_FD', '')
    if value.isdigit() and os.environ.get('FACTORY_STATE_LOCK_PATH') == str(lock):
        candidate = int(value)
        try:
            held, target = os.fstat(candidate), lock.stat()
            if (held.st_dev, held.st_ino) == (target.st_dev, target.st_ino):
                fd = candidate
        except OSError:
            pass
    own = fd is None
    if own:
        fd = os.open(lock, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        deadline = time.monotonic() + timeout
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    return 75
                time.sleep(.05)
        env = dict(os.environ, FACTORY_STATE_LOCK_FD=str(fd), FACTORY_STATE_LOCK_PATH=str(lock))
        return subprocess.call(command, env=env, pass_fds=(fd,))
    finally:
        if own:
            os.close(fd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lock', required=True)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--timeout', type=float, default=30)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.check:
        try:
            fd = int(os.environ['FACTORY_STATE_LOCK_FD'])
            held, target = os.fstat(fd), Path(args.lock).resolve().stat()
            if (held.st_dev, held.st_ino) != (target.st_dev, target.st_ino):
                return 1
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return 0
        except (KeyError, ValueError, OSError):
            return 1
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('command argv required')
    if not 0 <= args.timeout <= 3600:
        parser.error("invalid lock timeout")
    return run(args.lock, command, args.timeout)


if __name__ == '__main__':
    sys.exit(main())
