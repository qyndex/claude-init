#!/usr/bin/env python3
"""Terminate a foreground worker if its supervisor's liveness pipe closes."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys

spec = importlib.util.spec_from_file_location('supervisor', Path(__file__).with_name('factory-supervisor.py'))
supervisor = importlib.util.module_from_spec(spec); spec.loader.exec_module(supervisor)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--watch-fd', type=int, required=True)
    parser.add_argument('--inherit-fds', required=True)
    parser.add_argument('--db', required=True)
    parser.add_argument('--task', required=True)
    parser.add_argument('--owner', required=True)
    parser.add_argument('--token', type=int, required=True)
    parser.add_argument('--outcome', type=Path, required=True)
    parser.add_argument('--execution')
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    inherited = json.loads(args.inherit_fds)
    if not command or any(type(fd) is not int or fd < 0 or fd == args.watch_fd for fd in inherited):
        parser.error('invalid foreground worker/descriptors')
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
        worker = subprocess.Popen(command, start_new_session=True, pass_fds=tuple(inherited), env=environment, cwd=directory)
        while True:
            readable, _, _ = select.select([args.watch_fd], [], [], .05)
            if readable and os.read(args.watch_fd, 1) == b'':
                orphaned = True; reason = 'supervisor-lost'; break
            if stopped:
                reason = 'guardian-stopped'; break
            result = worker.poll()
            if result is not None:
                code = result if result >= 0 else 128 - result
                reason = 'worker-success' if code == 0 else 'worker-failure'
                break
        return code
    finally:
        try:
            if worker is not None:
                supervisor.terminate(worker, grace=.5)
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
