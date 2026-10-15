#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PY'
# AC-5, AC-12: primary protected planning assessment definition, no invocation.
import copy,hashlib,importlib.util,json,os,sys,tempfile
from pathlib import Path
root=Path(sys.argv[1])
def module(name,path):
 s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
m=module('intake_scout',root/'.claude/scripts/factory-intake-scout.py');r=module('profile_routing',root/'.claude/scripts/factory-routing.py')
assert hasattr(m,'load_assessment'),'protected primary assessor profile validator absent'
def reject(fn):
 try:fn()
 except (ValueError,OSError,KeyError,TypeError):return
 raise AssertionError('hostile assessor profile accepted')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
with tempfile.TemporaryDirectory() as d:
 base=Path(d).resolve();private=base/'private';private.mkdir(mode=0o700);candidate=base/'candidate';candidate.mkdir()
 binary=private/'native';binary.write_text('#!/bin/sh\ntouch '+str(private/'executed')+'\nexit 99\n');binary.chmod(0o700)
 settings=private/'settings.json';settings.write_text('{}');settings.chmod(0o600)
 mcp=private/'mcp.json';mcp.write_text('{"mcpServers":{}}');mcp.chmod(0o600)
 proof=private/'observation.json';proof.write_text(json.dumps({'schema_version':1,'runtime':'primary','model':'fixture-model','executable_sha256':sha(binary),'version':'2.1.295','capabilities':['foreground','model-selection','structured-output','tool-free','config-isolation','hook-failure-block']}));proof.chmod(0o600)
 capabilities=['foreground','model-selection','structured-output','tool-free','config-isolation','hook-failure-block']
 assessment={'argv':[str(binary),'--print','--model','{model}','--output-format','json','--tools','','--disallowedTools','mcp__*','--strict-mcp-config','--mcp-config',str(mcp),'--setting-sources','','--settings',str(settings),'--no-session-persistence'],'trusted_files':{str(p):sha(p) for p in [binary,settings,mcp,proof]},'version':'2.1.295','capabilities':capabilities,'observation':{'path':str(proof),'sha256':sha(proof)}}
 native={'kind':'claude-cli','model':'fixture-model','billing':'subscription','location':'local','allowed_model_usage':['fixture-model'],'command':[str(binary),'--safe-mode','--model','{model}','--output-format','json','--print'],'probe':{'argv':[str(binary),'--version'],'trusted_files':{str(binary):sha(binary)},'timeout':5}}
 checks={'kind':'command','model':None,'billing':'unknown','location':'actions','allowed_model_usage':[],'command':[str(binary)],'probe':{'argv':[str(binary)],'trusted_files':{str(binary):sha(binary)},'timeout':5}}
 profile={'schema_version':1,'enabled':True,'repository':'fixture/intake','source_roots':['src'],'stacks':{'python':{'tools':[str(binary)],'acceptance':[str(binary),'test']}},'runtimes':{'primary':copy.deepcopy(native),'fallback':copy.deepcopy(native),'review':{**copy.deepcopy(native),'location':'actions','command':native['command']+['--no-session-persistence']},'checks':checks},'roles':{role:{'primary':name,'fallbacks':['fallback'] if role=='planning' else [],'capabilities':sorted(r.FLOORS[role])} for role,name in [('planning','primary'),('implementation','primary'),('review','review'),('verification','checks'),('security','checks')]}}
 config=private/'profile.json'
 def save(doc=profile):config.write_text(json.dumps(doc));config.chmod(0o600)
 save();r.validate(profile);reject(lambda:m.load_assessment(config,[candidate]))
 profile['runtimes']['primary']['assessment']=assessment;save();result=m.load_assessment(config,[candidate]);assert result['runtime']=='primary' and result['model']=='fixture-model';assert result['argv'][3]=='fixture-model';assert result['capability_evidence']=='protected-observation';assert not (private/'executed').exists()
 def changed_assessment(change):
  doc=copy.deepcopy(profile);doc['runtimes']['primary']['assessment'].update(change);save(doc);reject(lambda:m.load_assessment(config,[candidate]));save()
 for args in [assessment['argv']+['--model','other'],assessment['argv']+['prompt'],assessment['argv']+['--resume','session'],assessment['argv']+['--bg'],assessment['argv']+['--safe-mode'],assessment['argv']+['--dangerously-skip-permissions'],assessment['argv']+['--fallback-model','other'],assessment['argv']+['--settings','{}'],assessment['argv']+['--api-key','secret']]:changed_assessment({'argv':args})
 for field,value in [('version','2.1.294'),('version','fixture version'),('capabilities',capabilities[:-1]),('extra',True)]:changed_assessment({field:value})
 args=assessment['argv'].copy();args[3]='other-model';changed_assessment({'argv':args})
 for p,content in [(settings,'{"env":{"ANTHROPIC_API_KEY":"bad"}}'),(settings,'{"hooks":{}}'),(mcp,'{"mcpServers":{"evil":{"command":"sh"}}}'),(mcp,'{"mcpServers":{},"extra":true}')]:
  original=p.read_bytes();p.write_text(content);doc=copy.deepcopy(profile);doc['runtimes']['primary']['assessment']['trusted_files'][str(p)]=sha(p);save(doc);reject(lambda:m.load_assessment(config,[candidate]));p.write_bytes(original);save()
 original=proof.read_bytes();doc=json.loads(original);doc['model']='other';proof.write_text(json.dumps(doc));bad=copy.deepcopy(profile);bad['runtimes']['primary']['assessment']['observation']['sha256']=sha(proof);bad['runtimes']['primary']['assessment']['trusted_files'][str(proof)]=sha(proof);save(bad);reject(lambda:m.load_assessment(config,[candidate]));proof.write_bytes(original);save()
 binary.write_text('changed');reject(lambda:m.load_assessment(config,[candidate]));binary.write_text('#!/bin/sh\ntouch '+str(private/'executed')+'\nexit 99\n');binary.chmod(0o700)
 settings.chmod(0o644);reject(lambda:m.load_assessment(config,[candidate]));settings.chmod(0o600)
 linked=private/'link';os.link(settings,linked);reject(lambda:m.load_assessment(config,[candidate]));linked.unlink()
 alias=private/'alias';alias.symlink_to(settings);bad=copy.deepcopy(profile);bad['runtimes']['primary']['assessment']['argv'][16]=str(alias);bad['runtimes']['primary']['assessment']['trusted_files'][str(alias)]=sha(settings);save(bad);reject(lambda:m.load_assessment(config,[candidate]));save()
 # Valid fallback assessor cannot compensate for missing primary assessor.
 bad=copy.deepcopy(profile);bad['runtimes']['fallback']['assessment']=bad['runtimes']['primary'].pop('assessment');save(bad);reject(lambda:m.load_assessment(config,[candidate]));save()
 config.chmod(0o644);reject(lambda:m.load_assessment(config,[candidate]));config.chmod(0o600)
 reject(lambda:m.load_assessment(config,[private]))
 print('assessment-profile: exact primary model/argv, pinned clean controls and bound observation; hostile overrides, fallback, changed/unsafe artifacts reject; no process launched')
PY
