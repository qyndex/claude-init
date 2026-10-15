"""Optional bounded fixture diagnostics; never imported by production/native code."""
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import threading
import time

MAX_BYTES=262144
NAMES={'assess','run_assessment','fresh_decision','current_request','proposal_material','process','publish_proposal','run','terminate_group','load_assessment'}

def _requested_file(label):
    value=os.environ.get('FACTORY_INTAKE_DIAGNOSTICS_DIR')
    if not value:return None
    try:
        directory=Path(value)
        info=directory.stat()
        if not directory.is_absolute() or directory.resolve()!=directory or not stat.S_ISDIR(info.st_mode) or info.st_uid!=os.getuid() or stat.S_IMODE(info.st_mode)!=0o700:return None
        descriptor,name=tempfile.mkstemp(prefix=label+'-',suffix='.jsonl',dir=directory)
        os.close(descriptor)
        return name
    except OSError:return None

def _chain(error):
    result=[];seen=set()
    while error is not None and id(error) not in seen and len(result)<4:
        seen.add(id(error));result.append({'type':type(error).__name__,'message':str(error)[:768]})
        error=error.__cause__ or error.__context__
    return result

def install(filename):
    if filename is None:return
    starts={}
    def trace(frame,event,arg):
        name=frame.f_code.co_name
        if '/.claude/scripts/factory-' not in frame.f_code.co_filename or name not in NAMES:return None
        record=None;identity=id(frame)
        if event=='call':
            starts[identity]=time.monotonic()
            if name=='run_assessment':
                record={'event':'assessment-call'}
                try:
                    value=json.loads(frame.f_locals['context']);text=value['request']['text']
                    record['request_sha256']=hashlib.sha256(text.encode()).hexdigest();record['request_chars']=len(text)
                    record['assessment_seconds']=frame.f_locals.get('assessment_seconds')
                except (KeyError,TypeError,ValueError):pass
        elif event=='exception' and not issubclass(arg[0],(StopIteration,GeneratorExit)):
            record={'event':'exception','chain':_chain(arg[1])}
        elif event=='return':
            if name=='run_assessment':record={'event':'assessment-return','elapsed':round(time.monotonic()-starts.get(identity,time.monotonic()),6)}
            starts.pop(identity,None)
        if record is not None:
            record.update(function=name,line=frame.f_lineno,at=time.monotonic())
            payload=(json.dumps(record,sort_keys=True)+'\n').encode()
            try:
                descriptor=os.open(filename,os.O_WRONLY|os.O_APPEND|os.O_NOFOLLOW)
                try:
                    info=os.fstat(descriptor)
                    if stat.S_ISREG(info.st_mode) and info.st_uid==os.getuid() and stat.S_IMODE(info.st_mode)==0o600 and info.st_size+len(payload)<=MAX_BYTES:os.write(descriptor,payload)
                finally:os.close(descriptor)
            except OSError:pass
        return trace
    sys.settrace(trace);threading.settrace(trace)

def install_requested(label):install(_requested_file(label))

def driver_prefix(label):
    filename=_requested_file(label)
    if filename is None:return ''
    return 'import runpy\nrunpy.run_path('+repr(str(Path(__file__).resolve()))+')["install"]('+repr(filename)+')\n'
