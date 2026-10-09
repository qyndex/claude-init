#!/usr/bin/env python3
"""Bound a foreground process group independently of agent prompt instructions."""
import argparse
import importlib.util
import signal
from pathlib import Path
import subprocess
import sys
import time

spec = importlib.util.spec_from_file_location('supervisor', Path(__file__).with_name('factory-supervisor.py'))
supervisor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(supervisor)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--timeout', type=float, required=True)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command or '--bg' in command or '--background' in command or not 0 < args.timeout <= 21600:
        parser.error('bounded foreground argv required')
    stopped = []
    previous = {}
    worker = None
    try:
        for sig in (signal.SIGTERM, signal.SIGINT):
            previous[sig] = signal.signal(sig, lambda signum, frame: stopped.append(signum))
        worker = subprocess.Popen(command, start_new_session=True)
        deadline = time.monotonic() + args.timeout
        while worker.poll() is None:
            if stopped:
                return 128 + stopped[0]
            if time.monotonic() >= deadline:
                return 124
            time.sleep(.05)
        return worker.returncode if worker.returncode >= 0 else 128 - worker.returncode
    finally:
        if worker is not None:
            supervisor.terminate(worker)
        for sig, handler in previous.items():
            signal.signal(sig, handler)


if __name__ == '__main__':
    sys.exit(main())
