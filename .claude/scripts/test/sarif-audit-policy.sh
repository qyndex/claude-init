#!/usr/bin/env bash
# Spec006 AC-11 / T329: authenticated exact-source exceptions, default off.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PY'
import copy,hashlib,json,os,re,subprocess,sys,tempfile
from pathlib import Path
root=Path(sys.argv[1]);gate=root/'.claude/scripts/check-sarif.sh';passed=0;failures=[]
rule='python.lang.security.audit.dangerous-subprocess-use-tainted-env-args.dangerous-subprocess-use-tainted-env-args'
def sha(raw):return hashlib.sha256(raw).hexdigest()
with tempfile.TemporaryDirectory(prefix='sarif-audit-policy-') as directory:
    base=Path(directory).resolve();source=base/'source';source.mkdir();(source/'runner.py').write_text('# intended command runner\npass\n')
    item={'rule':rule,'path':'runner.py','line':2,'sha256':sha((source/'runner.py').read_bytes()),'rationale':'Controlled exact-source fixture, not live approval','approval_ref':'fixture-review'}
    policy={'schema_version':1,'exceptions':[item]}
    result={'ruleId':rule,'locations':[{'physicalLocation':{'artifactLocation':{'uri':'runner.py'},'region':{'startLine':2}}}]}
    document={'version':'2.1.0','runs':[{'tool':{'driver':{'rules':[{'id':rule,'defaultConfiguration':{'level':'error'}}]}},'results':[result]}]}
    report=base/'report.sarif';registry=base/'policy.json'
    def check(name,doc=document,pol=policy,code=1,fragment='',approval='auto',options=True,root_path=None):
        global passed
        raw=json.dumps(doc).encode();report.write_bytes(raw)
        policy_raw=pol.encode() if isinstance(pol,str) else json.dumps(pol).encode();registry.write_bytes(policy_raw)
        args=['bash',str(gate),str(report)]
        if options:args+=['--audit-policy',str(registry),'--expected-registry-sha256',sha(policy_raw) if approval=='auto' else approval,'--source-root',str(root_path or source)]
        completed=subprocess.run(args,capture_output=True,text=True)
        assert report.read_bytes()==raw,(name,'raw SARIF mutated')
        if completed.returncode==code and fragment in completed.stdout+completed.stderr: passed+=1
        else: failures.append((name,completed.returncode,completed.stdout,completed.stderr))
    check('authenticated exact source',code=0,fragment='accepted exact-source audit exceptions: 1')
    check('default off',options=False,fragment='high/critical')
    check('missing protected approval',approval='',fragment='Audit policy blocked')
    check('mismatched protected digest',approval='0'*64,fragment='Audit policy blocked')
    changed=copy.deepcopy(policy);changed['exceptions'][0]['rationale']='Changed but still well-formed policy'
    check('registry mutation needs new external approval',pol=changed,approval=sha(json.dumps(policy).encode()),fragment='Audit policy blocked')
    check('malformed policy',pol='{',fragment='Audit policy blocked')
    for mutation in [lambda p:p.update(extra=True),lambda p:p.update(schema_version=True),lambda p:p.update(exceptions=[]),lambda p:p['exceptions'].append(copy.deepcopy(p['exceptions'][0]))]:
        value=copy.deepcopy(policy);mutation(value);check('invalid/duplicate registry',pol=value,fragment='Audit policy blocked')
    for key,value in [('rule',' '),('extra','unexpected'),('line',True),('line','2'),('line',0),('sha256','0'*64),('path','../runner.py'),('path','/runner.py'),('path','./runner.py'),('path','runner\\.py'),('approval_ref',''),('rationale','')]:
        changed=copy.deepcopy(policy);changed['exceptions'][0][key]=value;check('invalid record '+key,pol=changed,fragment='Audit policy blocked')
    duplicate=json.dumps(policy).replace('"schema_version": 1','"schema_version": 1, "schema_version": 1')
    check('duplicate JSON keys',pol=duplicate,fragment='Audit policy blocked')
    old=(source/'runner.py').read_bytes();(source/'runner.py').write_bytes(old+b'# mutation\n');check('modified source',fragment='Audit policy blocked');(source/'runner.py').write_bytes(old)
    (source/'runner.py').rename(source/'real.py');(source/'runner.py').symlink_to(source/'real.py');check('symlink file',fragment='Audit policy blocked');(source/'runner.py').unlink();(source/'real.py').rename(source/'runner.py')
    alias=base/'source-alias';alias.symlink_to(source,target_is_directory=True);check('symlink root',root_path=alias,fragment='Audit policy blocked')
    nested=source/'linked';nested.symlink_to(source,target_is_directory=True);changed=copy.deepcopy(policy);changed['exceptions'][0]['path']='linked/runner.py';check('symlink parent',pol=changed,fragment='Audit policy blocked');nested.unlink()
    for name,mutate in [
        ('changed rule',lambda r:r.update(ruleId='other',level='error')),
        ('changed path',lambda r:r['locations'][0]['physicalLocation']['artifactLocation'].update(uri='other.py')),
        ('changed line',lambda r:r['locations'][0]['physicalLocation']['region'].update(startLine=3)),
        ('missing location',lambda r:r.pop('locations')),
        ('multiple locations',lambda r:r['locations'].append(copy.deepcopy(r['locations'][0]))),
        ('foreign URI base',lambda r:r['locations'][0]['physicalLocation']['artifactLocation'].update(uriBaseId='OTHER')),
        ('null URI base',lambda r:r['locations'][0]['physicalLocation']['artifactLocation'].update(uriBaseId=None)),
        ('ambiguous artifact index',lambda r:r['locations'][0]['physicalLocation']['artifactLocation'].update(index=1)),
        ('encoded traversal',lambda r:r['locations'][0]['physicalLocation']['artifactLocation'].update(uri='%2e%2e/runner.py')),
    ]:
        doc=copy.deepcopy(document);mutate(doc['runs'][0]['results'][0]);check(name,doc,fragment='unapproved high/critical')
    doc=copy.deepcopy(document);doc['runs'][0]['originalUriBaseIds']={'%SRCROOT%':{'uri':'file:///foreign-root/'}}
    check('foreign SRCROOT mapping',doc,fragment='Invalid SARIF')
    doc=copy.deepcopy(document);doc['runs'][0]['originalUriBaseIds']={}
    check('unsupported base resolution even empty',doc,fragment='Invalid SARIF')
    doc=copy.deepcopy(document);doc['runs'][0]['invocations']=[{'workingDirectory':{'uri':'file:///foreign-root/'}}]
    check('unsupported invocation working directory',doc,fragment='Invalid SARIF')
    doc=copy.deepcopy(document);doc['runs'][0]['tool']['driver']['rules'][0]['properties']={'security-severity':'9.0'}
    check('inherited numeric high never waived',doc,fragment='unapproved high/critical')
    for severity in [7,9,'7.0']:
        doc=copy.deepcopy(document);doc['runs'][0]['results'][0]['properties']={'security-severity':severity};check('numeric high never waived',doc,fragment='unapproved high/critical')
    doc=copy.deepcopy(document);doc['runs'][0]['results'].append({'ruleId':'unapproved','level':'error','suppressions':[{'kind':'inSource','status':'accepted'}]});check('extra suppressed error',doc,fragment='unapproved high/critical')
    doc=copy.deepcopy(document);doc['runs'][0]['results'].append(copy.deepcopy(result));check('duplicate finding not blanket approved',doc,fragment='unapproved high/critical')
    doc=copy.deepcopy(document);doc['runs'][0]['results'][0]['level']='warning';check('warnings unchanged',doc,code=0,fragment='SARIF clean of high/critical')
    doc=copy.deepcopy(document);doc['runs'][0]['results'][0]['suppressions']=[{'kind':'external','status':'accepted'}];check('external policy alone grants approval',doc,code=0,fragment='accepted exact-source audit exceptions: 1')
    for args in [['--audit-policy',str(registry)],['--source-root',str(source)],['--bogus','x']]:
        p=subprocess.run(['bash',str(gate),str(report),*args],capture_output=True,text=True);assert p.returncode!=0,('partial policy CLI',args);passed+=1
    initial=json.loads((root/'.claude/security-audit-exceptions.json').read_text());assert len(initial['exceptions'])==2
    assert {r['path'] for r in initial['exceptions']}=={'.claude/scripts/factory-worker-guard.py','.claude/scripts/foreground-watchdog.py'}
    for entry in initial['exceptions']:assert sha((root/entry['path']).read_bytes())==entry['sha256']
    workflow=(root/'.github/workflows/semgrep.yml').read_text()
    default=workflow.split('  semgrep:\n',1)[1].split('\n  semgrep-audit:',1)[0]
    protected=workflow.split('\n  semgrep-audit:',1)[1]
    assert 'environment:' not in default and "vars.FACTORY_SECURITY_AUDIT_ENABLED != 'true'" in default
    assert 'environment: factory-security' in protected and "vars.FACTORY_SECURITY_AUDIT_ENABLED == 'true'" in protected
    assert 'vars.FACTORY_SECURITY_AUDIT_POLICY_SHA256' in protected and 'secrets.' not in protected
    step=protected.split('- name: Verify trusted audit source\n',1)[1].split('\n      - name:',1)[0]
    script=step.split('        run: |\n',1)[1];script='\n'.join(line[10:] for line in script.splitlines() if line.startswith('          '))
    bins=base/'bin';bins.mkdir();(bins/'git').write_text('#!/bin/sh\nprintf "%s\\n" "$FAKE_HEAD"\n');(bins/'git').chmod(0o755)
    env={'PATH':str(bins)+os.pathsep+os.environ['PATH'],'GITHUB_SHA':'a'*40,'FAKE_HEAD':'a'*40,'GITHUB_REF':'refs/heads/main'}
    for ref,head,ok in [('refs/heads/main','a'*40,True),('refs/heads/topic','a'*40,False),('refs/heads/main','b'*40,False)]:
        env.update(GITHUB_REF=ref,FAKE_HEAD=head);p=subprocess.run(['bash','-e','-o','pipefail','-c',script],env=env,capture_output=True,text=True);assert (p.returncode==0)==ok,(ref,head,p.stderr);passed+=1
print(f'SARIF exact-source audit policy: {passed} checks passed; {len(failures)} failed')
assert not failures, failures
PY
