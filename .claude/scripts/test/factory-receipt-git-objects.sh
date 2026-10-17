#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
import base64,importlib.util,json,subprocess,tempfile
from pathlib import Path
spec=importlib.util.spec_from_file_location('objects',Path('.claude/scripts/test/factory-receipt-git-objects.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
with tempfile.TemporaryDirectory() as folder:
 root=Path(folder)
 def git(*args,input=None):return subprocess.run(['git','-C',str(root),*args],input=input,capture_output=True,check=True).stdout
 git('init','-q');git('config','user.name','Fixture');git('config','user.email','fixture@example.invalid')
 (root/'a.txt').write_bytes(b'first\n');(root/'folder').mkdir();(root/'folder/b.txt').write_bytes(b'second\0\n')
 git('add','.');git('commit','-qm','first');first=git('rev-parse','HEAD').decode().strip()
 with m.GitObjects(root) as objects:
  for expression in ('HEAD:a.txt','HEAD:folder/b.txt'):
   oid,kind,raw=objects.read(expression)
   assert kind=='blob' and raw==git('show',expression)
  tree=git('rev-parse','HEAD^{tree}').decode().strip()
  rows=objects.tree(tree)
  assert [(row['mode'],row['type'],row['sha'],row['path']) for row in rows]==[(line.split()[0],line.split()[1],line.split()[2],line.split('\t')[1]) for line in git('ls-tree',tree).decode().splitlines()]
  assert next(row['size'] for row in rows if row['path']=='a.txt')==6
  assert objects.commit(first)=={'sha':first,'tree':{'sha':tree},'parents':[]}
  (root/'a.txt').write_bytes(b'changed\n');git('add','.');git('commit','-qm','second');second=git('rev-parse','HEAD').decode().strip()
  assert objects.read('HEAD:a.txt')[2]==b'changed\n','mutable ref was cached'
  assert objects.read(first+':a.txt')[2]==b'first\n','old immutable bytes changed'
  assert objects.commit(second)['parents']==[{'sha':first}]
  observed=objects.compare(first,second)
  assert observed['merge_base_commit']['sha']==git('merge-base',first,second).decode().strip()
  assert observed['ahead_by']==int(git('rev-list','--count',first+'..'+second))==1
  assert objects.compare(second,first) is None
  assert objects.compare(first,first)['status']=='identical'
  for name in ('a.txt','folder/b.txt','missing.txt'):
   assert objects.path_history(second,name)==tuple(git('log','--format=%H',second,'--',name).decode().splitlines())
  git('update-index','--chmod=+x','a.txt');git('commit','-qm','mode only');mode_only=git('rev-parse','HEAD').decode().strip()
  assert objects.path_history(mode_only,'a.txt')==tuple(git('log','--format=%H',mode_only,'--','a.txt').decode().splitlines()),'mode-only Git change omitted'
  (root/'a.txt').unlink();git('add','.');git('commit','-qm','delete');deleted=git('rev-parse','HEAD').decode().strip()
  assert objects.path_history(deleted,'a.txt')==tuple(git('log','--format=%H',deleted,'--','a.txt').decode().splitlines())
  # Native persistent tree writes must equal the original Git index path.
  import os
  index=root/'equivalence-index';environment=dict(os.environ,GIT_INDEX_FILE=str(index))
  def index_git(*args,input=None):return subprocess.run(['git','-C',str(root),*args],input=input,capture_output=True,check=True,env=environment).stdout
  blob=git('hash-object','-w','--stdin',input=b'opaque\0binary\n').decode().strip()
  current=git('rev-parse',deleted+'^{tree}').decode().strip()
  for base,entries in [(current,[{'path':'nested/tab\tline\nλ','mode':'100644','sha':blob}]),(tree,[{'path':'a.txt','mode':'100755','sha':blob}]),(current,[{'path':'folder/b.txt','mode':'0','sha':None}])]:
   index.unlink(missing_ok=True);index_git('read-tree',base)
   for item in entries:
    if item['sha'] is None:index_git('update-index','--force-remove','--',item['path'])
    else:index_git('update-index','--add','--cacheinfo',item['mode']+','+item['sha']+','+item['path'])
   expected=index_git('write-tree').decode().strip()
   actual=objects.write_tree(base,entries)
   assert actual==expected,'persistent native tree bytes differ'
  preserved=objects.write_tree(tree,[{'path':'nested/new','mode':'100644','sha':blob}])
  assert objects.read(preserved+':folder/b.txt')[2]==b'second\0\n','opaque sibling changed'
  assert git('rev-parse','HEAD').decode().strip()==deleted,'tree creation changed live ref'
  try:git('update-ref','HEAD',first,second)
  except subprocess.CalledProcessError:pass
  else:raise AssertionError('stale ref CAS accepted')
  # Fetch may add a pack after mktree initialized its object database.
  with tempfile.TemporaryDirectory() as remote:
   def remote_git(*args):return subprocess.run(['git','-C',remote,*args],capture_output=True,check=True).stdout
   remote_git('init','-q');remote_git('config','user.name','Fixture');remote_git('config','user.email','fixture@example.invalid')
   (Path(remote)/'fetched.txt').write_bytes(b'fetched immutable bytes');remote_git('add','.');remote_git('commit','-qm','fetched')
   git('config','fetch.unpackLimit','1');git('fetch',remote,'HEAD')
   fetched=git('rev-parse','FETCH_HEAD^{tree}').decode().strip()
   objects.reset_writer()
   changed=objects.write_tree(fetched,[{'path':'new','mode':'100644','sha':blob}])
   assert objects.read(changed+':fetched.txt')[2]==b'fetched immutable bytes'
  # Real divergent and merged ancestry must count both sides once, matching Git.
  git('checkout','-qb','side',first);(root/'side.txt').write_text('side');git('add','.');git('commit','-qm','side')
  side=git('rev-parse','HEAD').decode().strip()
  assert objects.compare(second,side) is None
  git('checkout','-q','-');git('merge','--no-ff','-qm','merge','side');merged=git('rev-parse','HEAD').decode().strip()
  assert objects.path_history(merged,'a.txt') is None
  for base in (first,second,side,merged):
   observed=objects.compare(base,merged)
   assert observed['ahead_by']==int(git('rev-list','--count',base+'..'+merged))
   assert observed['merge_base_commit']['sha']==git('merge-base',base,merged).decode().strip()
  try:objects.read('0'*40)
  except ValueError:pass
  else:raise AssertionError('missing Git object accepted')
  assert objects.read(first+':a.txt')[2]==b'first\n','missing object desynchronized batch'
print('persistent real Git object reads: exact binary/tree/commit equivalence, fresh mutable ref and missing-object recovery PASS')
PY
