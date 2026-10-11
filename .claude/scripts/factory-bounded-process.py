#!/usr/bin/env python3
"""Bound trusted subprocess output while reading; no post-capture memory spike."""
import os
import selectors
import signal
import subprocess
import time


def terminate_group(process):
    try:os.killpg(process.pid,signal.SIGTERM)
    except ProcessLookupError:return
    try:process.wait(timeout=.1)
    except subprocess.TimeoutExpired:pass
    observed=subprocess.run(['ps','-axo','pgid=,stat='],capture_output=True,text=True,check=True)
    alive=any(parts[0]==str(process.pid) and not parts[1].startswith('Z') for line in observed.stdout.splitlines() if len(parts:=line.split())==2)
    if not alive:return
    try:os.killpg(process.pid,signal.SIGKILL)
    except ProcessLookupError:pass
    process.wait(timeout=5)


def run(command,*,env,cwd,timeout,limit=1000000):
    if not 0<timeout<=60 or type(limit) is not int or not 1024<=limit<=8000000:
        raise ValueError('subprocess bounds invalid')
    process=subprocess.Popen(command,env=env,cwd=cwd,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
    buffers={'stdout':bytearray(),'stderr':bytearray()};deadline=time.monotonic()+timeout
    try:
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
                    output.extend(data)
            return subprocess.CompletedProcess(command,process.wait(),bytes(buffers['stdout']),bytes(buffers['stderr']))
    finally:
        terminate_group(process)
        process.stdout.close();process.stderr.close()
