#!/usr/bin/env python3
"""Bound trusted subprocess output while reading; no post-capture memory spike."""
import os
import selectors
import signal
import subprocess
import time


def terminate_group(process,grace=.1):
    try:os.killpg(process.pid,signal.SIGTERM)
    except ProcessLookupError:return
    try:process.wait(timeout=grace)
    except subprocess.TimeoutExpired:pass
    try:
        observed=subprocess.run(['/bin/ps','-axo','pgid=,stat='],capture_output=True,text=True,check=True,timeout=2,env={'PATH':'/usr/bin:/bin','HOME':'/nonexistent','LANG':'C','LC_ALL':'C'})
    except (OSError,subprocess.SubprocessError):
        try:os.killpg(process.pid,signal.SIGKILL)
        except ProcessLookupError:pass
        process.wait(timeout=5)
        raise ValueError('process cleanup status uncertain')
    alive=any(parts[0]==str(process.pid) and not parts[1].startswith('Z') for line in observed.stdout.splitlines() if len(parts:=line.split())==2)
    if not alive:return
    try:os.killpg(process.pid,signal.SIGKILL)
    except ProcessLookupError:pass
    process.wait(timeout=5)
    deadline=time.monotonic()+2
    while True:
        try:
            observed=subprocess.run(['/bin/ps','-axo','pgid=,stat='],capture_output=True,text=True,check=True,timeout=min(2,max(.01,deadline-time.monotonic())),env={'PATH':'/usr/bin:/bin','HOME':'/nonexistent','LANG':'C','LC_ALL':'C'})
        except (OSError,subprocess.SubprocessError):raise ValueError('process cleanup status uncertain')
        alive=any(parts[0]==str(process.pid) and not parts[1].startswith('Z') for line in observed.stdout.splitlines() if len(parts:=line.split())==2)
        if not alive:return
        if time.monotonic()>=deadline:raise ValueError('process group remains live after kill')
        time.sleep(.02)


def run(command,*,env,cwd,timeout,limit=1000000,stdin=None,max_timeout=60,aggregate_limit=None,pass_fds=(),on_spawn=None,termination_grace=None):
    if type(max_timeout) is not int or not 0<max_timeout<=300 or not 0<timeout<=max_timeout or type(limit) is not int or not 1024<=limit<=8000000:
        raise ValueError('subprocess bounds invalid')
    if aggregate_limit is not None and (type(aggregate_limit) is not int or not 1024<=aggregate_limit<=8000000):
        raise ValueError('subprocess aggregate bound invalid')
    if termination_grace is not None and (type(termination_grace) not in (int,float) or not .1<=termination_grace<=12):
        raise ValueError('subprocess termination grace invalid')
    process=subprocess.Popen(command,env=env,cwd=cwd,stdin=stdin,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True,pass_fds=tuple(pass_fds))
    buffers={'stdout':bytearray(),'stderr':bytearray()};deadline=time.monotonic()+timeout
    try:
        if on_spawn is not None:on_spawn(process)
        with selectors.DefaultSelector() as selector:
            for name in buffers:
                stream=getattr(process,name);os.set_blocking(stream.fileno(),False);selector.register(stream,selectors.EVENT_READ,name)
            while selector.get_map() or process.poll() is None:
                if time.monotonic()>=deadline:raise ValueError('trusted subprocess timeout')
                for event,unused in selector.select(min(.05,max(0,deadline-time.monotonic()))):
                    data=os.read(event.fd,65536)
                    if not data:selector.unregister(event.fileobj);continue
                    output=buffers[event.data]
                    if len(output)+len(data)>limit:raise ValueError('trusted subprocess output limit')
                    if aggregate_limit is not None and sum(len(value) for value in buffers.values())+len(data)>aggregate_limit:
                        raise ValueError('trusted subprocess aggregate output limit')
                    output.extend(data)
            return subprocess.CompletedProcess(command,process.wait(),bytes(buffers['stdout']),bytes(buffers['stderr']))
    finally:
        if termination_grace is None:terminate_group(process)
        else:terminate_group(process,grace=termination_grace)
        process.stdout.close();process.stderr.close()
