#!/usr/bin/env python3
"""Two-observation, bounded general PR discovery; scratch never authorizes receipts."""
from datetime import datetime
import hashlib
import json
import re


def require(value, message):
    if not value:raise ValueError(message)


def canonical(value):
    return json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False)


def instant(value):
    require(type(value) is str and len(value)<=40,'PR timestamp invalid')
    parsed=datetime.fromisoformat(value.replace('Z','+00:00'))
    require(parsed.tzinfo is not None,'PR timestamp timezone required')
    return parsed


def normalize(row, repository):
    require(type(row) is dict,'PR observation invalid')
    number=row.get('number');require(type(number) is int and 0<number<2**63,'PR number invalid')
    title=row.get('title');url=row.get('html_url')
    require(type(title) is str and len(title)<=10000 and type(url) is str
            and url=='https://github.com/'+repository+'/pull/'+str(number),'PR display identity invalid')
    base=row.get('base');head=row.get('head')
    require(type(base) is dict and type(base.get('repo')) is dict and base['repo'].get('full_name')==repository
            and type(base.get('ref')) is str and 0<len(base['ref'])<=255 and type(head) is dict
            and type(head.get('sha')) is str and re.fullmatch('[0-9a-f]{40}',head['sha']),'PR repository/head invalid')
    at=row.get('merged_at');merge=row.get('merge_commit_sha')
    if at is not None:
        instant(at);require(type(merge) is str and re.fullmatch('[0-9a-f]{40}',merge),'PR merge identity invalid')
    else:require(merge is None or type(merge) is str and re.fullmatch('[0-9a-f]{40}',merge),'PR closed identity invalid')
    return {'number':number,'title':title,'html_url':url,'merged_at':at,'merge_commit_sha':merge,
            'head':{'sha':head['sha']},'base':{'ref':base['ref'],'repo':{'full_name':repository}}}


def compatible_layout(pages, phase, next_page, size):
    """Recognize only current 25-row or historical 100-row scratch layouts."""
    if size not in (25,100):return False
    if phase=='baseline':
        return len(pages)==next_page-1 and all(r['count']==size for r in pages)
    return bool(pages) and pages[-1]['count']<size and all(r['count']==size for r in pages[:-1]) and (next_page==len(pages)+1 if phase=='ready' else next_page<=len(pages))


def scan(db, api, stream, repository, branch, origin, until):
    """Eight 25-row pages per call; two exact full observations before internal ready return."""
    require(api.repo==repository and re.fullmatch('[0-9a-f]{64}',stream),'PR source binding invalid')
    low,high=instant(origin),instant(until);require(low<high,'PR interval invalid')
    db.execute('CREATE TABLE IF NOT EXISTS reporting_pr_scans(stream TEXT PRIMARY KEY,repository TEXT NOT NULL,branch TEXT NOT NULL,origin TEXT NOT NULL,until TEXT NOT NULL,phase TEXT NOT NULL,next_page INTEGER NOT NULL)')
    db.execute('CREATE TABLE IF NOT EXISTS reporting_pr_pages(stream TEXT NOT NULL,page INTEGER NOT NULL,fingerprint TEXT NOT NULL,count INTEGER NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(stream,page))')
    def reset():
        db.execute('DELETE FROM reporting_pr_pages WHERE stream=?',(stream,))
        db.execute('INSERT OR REPLACE INTO reporting_pr_scans VALUES(?,?,?,?,?,?,?)',(stream,repository,branch,origin,until,'baseline',1))
    state=db.execute('SELECT * FROM reporting_pr_scans WHERE stream=?',(stream,)).fetchone()
    if state is None or tuple(state[name] for name in ('repository','branch','origin','until'))!=(repository,branch,origin,until):reset()
    state=db.execute('SELECT * FROM reporting_pr_scans WHERE stream=?',(stream,)).fetchone()
    phase,page=state['phase'],state['next_page']
    require(phase in ('baseline','compare','ready') and type(page) is int and 0<page<2**63,'PR progress invalid')
    saved=db.execute('SELECT * FROM reporting_pr_pages WHERE stream=? ORDER BY page',(stream,)).fetchall()
    candidates=[];seen=set()
    for index,item in enumerate(saved,1):
        require(item['page']==index and type(item['count']) is int and 0<=item['count']<=100
                and type(item['fingerprint']) is str and re.fullmatch('[0-9a-f]{64}',item['fingerprint'])
                and type(item['payload']) is str,'PR page checkpoint invalid')
        rows=json.loads(item['payload']);require(type(rows) is list and len(rows)<=item['count'] and canonical(rows)==item['payload'],'PR candidates invalid')
        for row in rows:
            clean=normalize(row,repository)
            require(clean==row and clean['merged_at'] is not None and clean['base']['ref']==branch
                    and low<instant(clean['merged_at'])<=high and clean['number'] not in seen,'PR candidate binding invalid')
            seen.add(clean['number']);candidates.append(clean)
    current=compatible_layout(saved,phase,page,25)
    require(current or compatible_layout(saved,phase,page,100),'PR checkpoint cursor invalid')
    # Authenticated historical scratch remains restorable, but incompatible page
    # boundaries must restart observations; delivery/receipt tables are untouched.
    if not current:
        reset();phase='baseline';page=1;candidates=[];seen=set()
    # Ready scratch is never accepted on a subsequent process without a fresh pass.
    if phase=='ready':phase='compare';page=1
    for _ in range(8):
        endpoint=f'repos/{repository}/pulls?state=closed&sort=created&direction=asc&per_page=25&page={page}'
        raw=api.request(endpoint)
        require(type(raw) is list and len(raw)<=25,'PR source page invalid')
        rows=[normalize(row,repository) for row in raw]
        require(len({r['number'] for r in rows})==len(rows),'PR page duplicate identity')
        fingerprint=hashlib.sha256(canonical(rows).encode()).hexdigest()
        selected=[r for r in rows if r['merged_at'] is not None and r['base']['ref']==branch and low<instant(r['merged_at'])<=high]
        if phase=='baseline':
            if any(r['number'] in seen for r in selected):reset();return {'status':'incomplete','phase':'pull-requests','reason':'PR membership shifted'}
            db.execute('INSERT INTO reporting_pr_pages VALUES(?,?,?,?,?)',(stream,page,fingerprint,len(rows),canonical(selected)))
            seen.update(r['number'] for r in selected);candidates.extend(selected)
            if len(rows)<25:phase='compare';page=1
            else:page+=1
        else:
            expected=db.execute('SELECT * FROM reporting_pr_pages WHERE stream=? AND page=?',(stream,page)).fetchone()
            if expected is None or expected['fingerprint']!=fingerprint or expected['count']!=len(rows) or expected['payload']!=canonical(selected):
                reset();return {'status':'incomplete','phase':'pull-requests','reason':'PR membership shifted'}
            if len(rows)<25:
                db.execute("UPDATE reporting_pr_scans SET phase='ready',next_page=? WHERE stream=?",(page+1,stream))
                return {'status':'complete','rows':candidates}
            page+=1
        db.execute('UPDATE reporting_pr_scans SET phase=?,next_page=? WHERE stream=?',(phase,page,stream))
    return {'status':'incomplete','phase':'pull-requests','reason':'PR source scan in progress'}
