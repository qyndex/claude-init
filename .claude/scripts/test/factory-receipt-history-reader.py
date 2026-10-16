"""Fresh-process real Git reporting fixture; no cloud calls or source artifact proof."""
import copy
import json
from pathlib import Path
import sys
from urllib.parse import parse_qs, urlparse


def runs(metadata, policy, start, end):
    class Runs:
        repo = policy['repository']
        def get(self, target):
            prefix = 'repos/'+self.repo+'/actions/runs/'
            target = target.lstrip('/')
            if target.startswith(prefix) and target[len(prefix):].isdigit():
                identity = int(target[len(prefix):])
                return copy.deepcopy(next(row for row in metadata if row['id'] == identity))
            raise RuntimeError('source artifacts expired; retained proof required')
        def request(self, target, **kwargs):
            parsed = urlparse(target)
            assert parsed.path.lstrip('/') == f'repos/{self.repo}/actions/workflows/{policy["receipts"]["workflow_id"]}/runs'
            query = parse_qs(parsed.query);lo,hi = query.get('created',[start+'..'+end])[0].split('..')
            assert query.get('branch',[policy['base_branch']]) == [policy['base_branch']]
            size=int(query['per_page'][0]);page=int(query['page'][0])
            selected=sorted((copy.deepcopy(row) for row in metadata if lo<=row['created_at']<=hi),key=lambda row:(row['created_at'],row['id']),reverse=True)
            # The real filtered API exposes at most1000results, even if more exist.
            return {'total_count':min(1000,len(selected)),'workflow_runs':selected[:1000][(page-1)*size:page*size]}
        def source(self, *args):
            raise RuntimeError('source artifacts expired; retained proof required')
    return Runs()


def main():
    context=json.loads(sys.stdin.read())
    namespace={'context':context,'history_runs':runs,'Path':Path}
    fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
    pipeline=Path('.claude/scripts/test/factory-receipt-projection-windows.sh').read_text().split("cases=r'''\n",1)[1].split(' # Two distinct approved tasks',1)[0]
    provider=Path('.claude/scripts/test/factory-receipt-history.sh').read_text().split("cases=r'''\n",1)[1].split(' total=1001;end=',1)[0]
    case=r'''
 import shutil,sqlite3
 git('fetch',context['work'],ref);loaded=out('rev-parse','FETCH_HEAD');git('update-ref',ref,loaded,initial)
 shutil.copyfile(context['trust'],trust);shutil.copyfile(context['approval'],approval)
 policy=context['policy'];store=context['store'];stream=context['stream'];end=context['end']
 initial=json.loads(approval.read_bytes())['bootstrap_sha'];tree=json.loads(approval.read_bytes())['bootstrap_tree']
 before=out('rev-parse',ref)
 if context['mode']=='projection':
  db=Path(context['database'])
  result=a.reconstruct_interval(HistoryState(),policy,db,trust,store,approval,stream,interval_end=end,history_head=context['selected'],campaign=context['campaign'])
  assert result['projection_complete'] and result['facts_count']==1001,result
  with sqlite3.connect(db) as sql:
   counts={name:sql.execute('SELECT count(*) FROM '+name).fetchone()[0] for name in ('delivery_receipts','delivery_provenance','delivery_times','delivery_trust','delivery_interval')}
  assert set(counts.values())=={1001},counts
  print(json.dumps({'fresh_process':True,'result':result,'sqlite_counts':counts}))
 elif context['mode']=='coverage':
  ds=importlib.util.spec_from_file_location('history_discovery',scripts/'factory-receipt-discovery.py');d=importlib.util.module_from_spec(ds);ds.loader.exec_module(d)
  provider=history_runs(context['metadata'],policy,'2026-10-15T00:00:00Z',end)
  result=d.coverage(provider,HistoryState(),policy,trust,store,approval,stream,interval_end=end,projection_end=end,history_head=context['selected'],campaign=context['campaign'],page_size=100)
  assert result['coverage_complete'] and result['source_partition_complete'] and result['frozen_projection_complete'] and result['task_credit'] is False and result['all_history_complete'] is False,result
  print(json.dumps({'fresh_process':True,'result':result}))
 else:raise AssertionError('unknown fixture mode')
 assert out('rev-parse',ref)==before and git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
'''
    exec(compile(fixture+pipeline+provider+case,'fresh1001-retained-history-reader','exec'),namespace)


if __name__=='__main__':
    main()
