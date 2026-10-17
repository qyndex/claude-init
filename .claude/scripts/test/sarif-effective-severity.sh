#!/usr/bin/env bash
# Spec006 AC-5: effective severity, identity and malformed-output behavior.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PY'
import copy,json,pathlib,subprocess,sys,tempfile
root=pathlib.Path(sys.argv[1]); gate=root/'.claude/scripts/check-sarif.sh'
passed=0; failed=[]
def doc(result=None,rules=None):
    run={'results':[] if result is None else [result]}
    if rules is not None: run['tool']={'driver':{'rules':rules}}
    return {'version':'2.1.0','runs':[run]}
def rule(level='error',**extra):
    return dict(id='x',defaultConfiguration={'level':level},**extra)
def check(name,value,exitcode,fragment):
    global passed
    p=pathlib.Path(tmp)/'input.sarif'
    p.write_text(value if isinstance(value,str) else json.dumps(value))
    result=subprocess.run(['bash',str(gate),str(p)],capture_output=True,text=True)
    output=result.stdout+result.stderr
    if result.returncode==exitcode and fragment in output: passed+=1
    else: failed.append(f'{name}: expected exit{exitcode}/{fragment!r}; got{result.returncode}/{output!r}')
with tempfile.TemporaryDirectory() as tmp:
    check('unknown-rule-index-warning',doc({'ruleId':'x','ruleIndex':-1},[rule('warning')]),0,'SARIF clean')
    check('unknown-reference-index-warning',doc({'rule':{'id':'x','index':-1}},[rule('warning')]),0,'SARIF clean')
    check('unknown-rule-index-inherits-error',doc({'ruleId':'x','ruleIndex':-1},[rule()]),1,'high/critical')
    check('unknown-reference-index-inherits-error',doc({'rule':{'id':'x','index':-1}},[rule()]),1,'high/critical')
    check('unknown-index-no-id-default',doc({'ruleIndex':-1}),0,'SARIF clean')
    check('unknown-reference-no-id-default',doc({'rule':{'index':-1}}),0,'SARIF clean')
    check('unknown-index-numeric-high',doc({'ruleId':'x','ruleIndex':-1},[rule('warning',properties={'security-severity':9})]),1,'high/critical')
    check('unknown-index-explicit-warning-wins',doc({'ruleId':'x','ruleIndex':-1,'level':'warning'},[rule()]),0,'SARIF clean')
    check('unknown-index-structured-positive',doc({'ruleId':'x','ruleIndex':-1,'rule':{'id':'x','index':0}},[rule('warning')]),1,'Invalid SARIF')
    check('positive-index-structured-unknown',doc({'ruleId':'x','ruleIndex':0,'rule':{'id':'x','index':-1}},[rule('warning')]),1,'Invalid SARIF')
    check('equal-unknown-index-warning',doc({'ruleId':'x','ruleIndex':-1,'rule':{'index':-1}},[rule('warning')]),0,'SARIF clean')
    check('equal-unknown-index-inherits-error',doc({'ruleId':'x','ruleIndex':-1,'rule':{'index':-1}},[rule()]),1,'high/critical')
    check('equal-concrete-index-warning',doc({'ruleId':'x','ruleIndex':0,'rule':{'index':0}},[rule('warning')]),0,'SARIF clean')
    check('equal-concrete-index-inherits-error',doc({'ruleId':'x','ruleIndex':0,'rule':{'index':0}},[rule()]),1,'high/critical')
    check('unknown-index-conflicting-id',doc({'ruleId':'x','ruleIndex':-1,'rule':{'id':'y','index':-1}},[rule()]),1,'Invalid SARIF')
    check('rule-id-default-error',doc({'ruleId':'x'},[rule()]),1,'high/critical')
    check('rule-index-default-error',doc({'ruleIndex':0},[rule()]),1,'high/critical')
    check('structured-index-default-error',doc({'rule':{'index':0}},[rule()]),1,'high/critical')
    check('id-and-index-default-error',doc({'ruleId':'x','ruleIndex':0},[rule()]),1,'high/critical')
    check('explicit-warning-wins',doc({'ruleId':'x','level':'warning'},[rule()]),0,'SARIF clean')
    check('explicit-error-wins',doc({'ruleId':'x','level':'error'},[rule('warning')]),1,'high/critical')
    check('absent-config-default-warning',doc({'ruleId':'x'},[{'id':'x'}]),0,'SARIF clean')
    check('unknown-id-no-descriptor',doc({'ruleId':'unknown'},[]),0,'SARIF clean')
    check('clean',doc(),0,'SARIF clean')
    for kind in ['pass','open','informational','notApplicable','review']:
        check(f'{kind}-default-none',doc({'ruleId':'x','kind':kind},[rule()]),0,'SARIF clean')
        check(f'{kind}-explicit-none',doc({'ruleId':'x','kind':kind,'level':'none'},[rule()]),0,'SARIF clean')
        check(f'{kind}-invalid-level',doc({'ruleId':'x','kind':kind,'level':'error'},[rule()]),1,'Invalid SARIF')
    check('result-numeric-high',doc({'level':'warning','properties':{'security-severity':'7.0'}}),1,'high/critical')
    check('rule-numeric-high-index',doc({'ruleIndex':0},[rule('warning',properties={'security-severity':'9.0'})]),1,'high/critical')
    check('rule-numeric-high-id',doc({'ruleId':'x'},[rule('warning',properties={'security-severity':'8.0'})]),1,'high/critical')
    check('numeric-low',doc({'properties':{'security-severity':'6.9'}}),0,'SARIF clean')
    check('result-numeric-zero-wins',doc({'ruleId':'x','properties':{'security-severity':0}},[rule('warning',properties={'security-severity':9})]),0,'SARIF clean')
    check('nonfail-rule-high',doc({'ruleId':'x','kind':'pass'},[rule(properties={'security-severity':9})]),0,'SARIF clean')
    check('hierarchical-id-index',doc({'ruleId':'x/detail','ruleIndex':0},[rule()]),1,'high/critical')
    check('conflicting-id-index',doc({'ruleId':'y','ruleIndex':0,'level':'warning'},[rule()]),1,'Invalid SARIF')
    check('conflicting-structured-id',doc({'ruleId':'x','rule':{'id':'y','index':0}},[rule()]),1,'Invalid SARIF')
    check('conflicting-structured-index',doc({'ruleIndex':0,'rule':{'index':1}},[rule(),{'id':'y'}]),1,'Invalid SARIF')
    for index in [-2,-1.5,1,0.5,True,None,'0','-1']:
        check(f'invalid-index-{index}',doc({'ruleIndex':index},[rule()]),1,'Invalid SARIF')
    for index in [-2,-1.5,True,None,'-1']:
        check(f'invalid-reference-index-{index}',doc({'rule':{'id':'x','index':index}},[rule('warning')]),1,'Invalid SARIF')
    check('duplicate-id-ambiguous',doc({'ruleId':'x'},[rule(),rule('warning')]),1,'Invalid SARIF')
    check('duplicate-id-index-disambiguates',doc({'ruleId':'x','ruleIndex':1},[rule(),rule('warning')]),0,'SARIF clean')
    for key,value in [('level','fatal'),('level',None),('kind','bogus'),('kind',None),('ruleId',None),('rule',None)]:
        check(f'invalid-result-{key}-{value}',doc({key:value}),1,'Invalid SARIF')
    for severity in ['not numeric','NaN','Infinity',True,None,{}]:
        check(f'invalid-numeric-{severity}',doc({'properties':{'security-severity':severity}}),1,'Invalid SARIF')
    check('bad-default-level',doc({'ruleId':'x'},[rule('fatal')]),1,'Invalid SARIF')
    check('null-default',doc({'ruleId':'x'},[{'id':'x','defaultConfiguration':None}]),1,'Invalid SARIF')
    for tool in [None,False,{'driver':None},{'driver':False}]:
        invalid=doc(); invalid['runs'][0]['tool']=tool
        check(f'invalid-tool-{tool}',invalid,1,'Invalid SARIF')
    extensions=doc({'ruleId':'x'}); extensions['runs'][0]['tool']={'driver':{},'extensions':[{'rules':[rule()]}]}
    check('unresolved-extension-only-id',extensions,1,'Invalid SARIF')
    check('empty-rule-reference',doc({'rule':{}}),1,'Invalid SARIF')
    external=doc({'ruleId':'x'}); external['runs'][0]['externalPropertyFileReferences']={'toolDriver':{'location':{'uri':'rules.json'}}}
    check('external-rule-file',external,1,'Invalid SARIF')
    inline=doc(); inline['inlineExternalProperties']=[{'results':[{'level':'error'}]}]
    check('inline-external-results',inline,1,'Invalid SARIF')
    check('unavailable-extension',doc({'rule':{'index':0,'toolComponent':{'index':0}}},[rule()]),1,'Invalid SARIF')
    override=doc({'ruleId':'x'},[rule('warning')]); override['runs'][0]['invocations']=[{'ruleConfigurationOverrides':[{'descriptor':{'id':'x'},'configuration':{'level':'error'}}]}]
    check('unresolved-configuration-override',override,1,'Invalid SARIF')
    check('missing-results',{'version':'2.1.0','runs':[{}]},1,'Invalid SARIF')
    check('malformed-json','{',1,'Invalid SARIF')
    check('multiple-documents',json.dumps(doc())+'\n'+json.dumps(doc()),1,'Invalid SARIF')
    check('empty-document','',1,'SARIF missing or empty')
print(f'SARIF effective severity: {passed} passed; {len(failed)} failed')
for failure in failed: print('FAIL '+failure)
assert not failed, '\n'.join(failed)
PY
