import importlib.util,os,sqlite3,tempfile
from pathlib import Path
root=Path.cwd();spec=importlib.util.spec_from_file_location('codec',root/'.claude/scripts/factory-encrypted-feedback.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp).resolve()/'state.sqlite'
 with sqlite3.connect(p) as db:
  db.execute('CREATE TABLE feedback_checkpoint_identity(id INTEGER PRIMARY KEY CHECK(id=1),repository TEXT NOT NULL)');db.execute("INSERT INTO feedback_checkpoint_identity VALUES(1,'org/repo')")
 p.chmod(0o600);original=p.read_bytes();assert m.validate_database(p,'org/repo')==original
 connect=m.sqlite3.connect
 def forbidden(*args,**kwargs):raise AssertionError('unsafe file reached SQLite decoder')
 m.sqlite3.connect=forbidden
 def rejected():
  try:m.validate_database(p,'org/repo')
  except ValueError:return
  raise AssertionError('unsafe file accepted')
 try:
  p.chmod(0o644);rejected();p.chmod(0o600)
  alias=p.with_name('alias');os.link(p,alias);rejected();alias.unlink()
  saved=m.MAX_DATABASE;m.MAX_DATABASE=len(original)-1;rejected();m.MAX_DATABASE=saved
  p.write_bytes(b'');rejected();p.write_bytes(original)
  target=p.with_name('target');p.rename(target);p.symlink_to(target);rejected();p.unlink();target.rename(p)
  journal=Path(str(p)+'-journal');journal.write_bytes(b'uncertain');rejected();journal.unlink()
 finally:m.sqlite3.connect=connect
 # AC-9/AC-10: the second identity check observes a change during the finite descriptor read.
 fstat=m.os.fstat;calls=[0]
 def changed(fd):
  calls[0]+=1
  if calls[0]==2:os.utime(p,ns=(p.stat().st_atime_ns,p.stat().st_mtime_ns+1000000))
  return fstat(fd)
 m.os.fstat=changed
 try:rejected()
 finally:m.os.fstat=fstat
print('AC-9/AC-10: unsafe mode, hardlink, finite size, empty file, symlink and detached journal reject before SQLite; changed descriptor identity rejects stable capture')
