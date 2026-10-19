#!/usr/bin/env python3
"""Bounded protected reporting maintenance; progress is never delivery authority."""
import importlib.util
from pathlib import Path
from urllib.parse import quote


def load(name, filename):
    spec=importlib.util.spec_from_file_location(name,Path(__file__).with_name(filename))
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value


archive=load('maintenance_archive','factory-receipt-archive.py')
discovery=load('maintenance_discovery','factory-receipt-discovery.py')
state=load('maintenance_state','factory-git-state.py')
require=archive.require
FIELDS={'schema_version','repository','stream','binding','interval_end','previous_blob','previous_interval_end',
        'phase','remaining','review_blob','review_cursor','history_head','campaign','page','offset',
        'records_count','trust_sha256','policy_sha256','review_watch_count','review_watch_segments','source_epoch'}
PHASES=('backfill','review','checkpoint','stage','ready','verify')
_REPORTING=object()
_SELECT_REPORTING=object()
_ACKNOWLEDGE=object()


def _journal(value, expected):
    require(type(value) is dict and set(value)==FIELDS and type(value['schema_version']) is int
            and value['schema_version']==1 and value['repository']==expected['repository']
            and value['stream']==expected['stream'] and archive.canonical(value['binding'])==archive.canonical(expected['binding'])
            and type(value['phase']) is str and value['phase'] in PHASES, 'maintenance protected journal binding differs')
    require(type(value['interval_end']) is str and len(value['interval_end'])<=40
            and archive.instant(value['interval_end']).microsecond==0, 'maintenance interval invalid')
    require(value['previous_blob'] is None or archive.state_paths.valid_hash(value['previous_blob'],40), 'maintenance previous blob invalid')
    require(value['previous_interval_end'] is None or (type(value['previous_interval_end']) is str
            and archive.instant(value['previous_interval_end'])<=archive.instant(value['interval_end'])), 'maintenance previous interval invalid')
    require(all(type(value[key]) is int and 0<=value[key]<10**12 for key in ('remaining','records_count','offset','review_watch_count','review_watch_segments','source_epoch'))
            and type(value['page']) is int and 1<=value['page']<10**12, 'maintenance counters invalid')
    require(value['review_blob'] is None or archive.state_paths.valid_hash(value['review_blob'],40), 'maintenance review observation invalid')
    require(value['review_cursor'] is None or (type(value['review_cursor']) is dict and set(value['review_cursor'])=={'segment','row'}
            and all(type(n) is int and 0<=n<10**12 for n in value['review_cursor'].values())), 'maintenance review cursor invalid')
    require(all(value[key] is None or archive.state_paths.valid_hash(value[key],40 if key=='history_head' else 64)
                for key in ('history_head','campaign'))
            and all(archive.state_paths.valid_hash(value[key],64) for key in ('trust_sha256','policy_sha256')), 'maintenance selectors invalid')
    require((value['previous_blob'] is None)==(value['previous_interval_end'] is None), 'maintenance previous pair differs')
    require((value['review_blob'] is None)==(value['review_cursor'] is None), 'maintenance review pair differs')
    require(value['review_blob'] is None or (value['phase']=='review' and value['review_watch_count']>0
            and value['review_watch_segments']>0 and value['review_cursor']['segment']<value['review_watch_segments']),
            'maintenance review cursor outside watch')
    require(value['phase']!='review' or value['remaining']<=value['review_watch_count'], 'maintenance review remaining exceeds watch')
    require(all((value[key] is not None)==(value['phase'] in ('stage','ready','verify')) for key in ('history_head','campaign')),
            'maintenance phase selectors differ')
    require(len(archive.canonical(value))<=16384, 'maintenance journal capacity gap')
    return value


def maintain(source_api, state_api, policy, trust_path, store, approval_path, *, interval_end, trust_mode='profile', _operation=None):
    """One origin advancement and at most one dependent bounded phase action.

    Every invocation reloads actual protected progress. Caller interval/returned
    selectors choose requested work only; fresh coverage and typed reconstruction
    remain mandatory before reporting. No persistent local database is accepted.
    """
    acknowledge=type(_operation) is tuple and len(_operation)==3 and _operation[0] is _ACKNOWLEDGE
    scheduled=type(_operation) is tuple and len(_operation)==2 and (_operation[0] is _REPORTING or _operation[0] is _SELECT_REPORTING)
    require(_operation is None or _operation is _REPORTING or _operation is _SELECT_REPORTING or scheduled or (acknowledge and
            archive.state_paths.valid_hash(_operation[1],40) and archive.state_paths.valid_hash(_operation[2],64)),
            'maintenance internal operation invalid')
    reporting=_operation is _REPORTING or (scheduled and _operation[0] is _REPORTING)
    selecting=_operation is _SELECT_REPORTING or (scheduled and _operation[0] is _SELECT_REPORTING)
    reporting_cursor=_operation[1] if scheduled else None
    if scheduled:
        require(type(reporting_cursor) is str and len(reporting_cursor)<=40
                and archive.instant(reporting_cursor).microsecond==0
                and archive.instant(reporting_cursor)<=archive.instant(interval_end), 'maintenance report cursor invalid')
    require(source_api.repo==state_api.repo==policy['repository']==store['repository'] and trust_mode in ('profile','legacy'),
            'maintenance repository/trust mode differs')
    require(type(interval_end) is str and len(interval_end)<=40 and archive.instant(interval_end).microsecond==0,
            'maintenance cutoff requires exact seconds')
    require(archive.instant(interval_end)<=archive.datetime.datetime.now(archive.datetime.timezone.utc),
            'maintenance cutoff is in future')
    # Production passes the same RoutedAPI to both roles; its actual raw response
    # accounting survives every phase. This additional envelope also bounds local
    # adapter composition, including fixed-query raw batch responses.
    calls=consumed=0
    def begin():
        nonlocal calls
        require(calls<2048 and consumed<33554432,'maintenance invocation capacity gap')
        calls+=1
    def observe(value, *, batch=False):
        nonlocal consumed
        size=value.get('raw_bytes') if batch and type(value) is dict else len(value) if type(value) is bytes else len(archive.canonical(value))
        require(type(size) is int and 0<size<=2097152,'maintenance response capacity gap')
        consumed+=size;require(calls<=2048 and consumed<=33554432,'maintenance invocation capacity gap')
        return value
    class State:
        repo=state_api.repo
        def request(self,path,method='GET',payload=None):
            begin();return observe(state_api.request(path,method,payload))
    class Source:
        repo=source_api.repo
        def get(self,path):
            begin();return observe(source_api.get(path))
        def request(self,path,**kwargs):
            require(kwargs.get('method','GET')=='GET','maintenance source must be read-only')
            begin();return observe(source_api.request(path,**kwargs))
        def source(self,path,sha):
            begin();return observe(source_api.source(path,sha))
    api=State();source=Source()
    for name in ('read_blobs','read_pull_requests'):
        method=getattr(state_api,name,None)
        if callable(method):
            def batch(repository_id,selectors,method=method):
                begin();return observe(method(repository_id,selectors),batch=True)
            setattr(api,name,batch)
    progress=archive.advance_origin(api,approval_path,commit_budget=16,tree_pages=4)
    result={'status':'incomplete','phase':'origin','coverage_complete':False,'all_history_complete':False,'task_credit':False}
    if not progress['frozen_complete']:return result
    anchor=archive.verify_bootstrap(api,approval_path);root='repos/'+api.repo;stream=archive.archive_stream(api.repo)
    require(archive.instant(anchor['coverage_from'])<=archive.instant(interval_end), 'maintenance cutoff precedes approved origin')
    validated_trust=archive.receipts.load_receipt_trust(trust_path,api.repo,mode='report')
    with Path(trust_path).open('rb') as trust_source:trust_raw=trust_source.read(262145)
    require(0<len(trust_raw)<=262144 and archive.canonical(archive.document(trust_raw))==archive.canonical(validated_trust),
            'maintenance trust changed during validation')
    trust_hash=archive.digest(trust_raw);policy_hash=archive.receipts.coordinator.policy_hash(policy)
    binding={key:anchor[key] for key in ('repository_id','branch','bootstrap_sha','bootstrap_tree','coverage_from','writer_app_id','approval_sha256')}
    # Source identity rotations need reviewed migration, unlike mutable policy/trust content.
    binding.update(workflow_id=policy['receipts']['workflow_id'],source_branch=policy['base_branch'],trust_mode=trust_mode)
    role=archive.digest(archive.canonical(['reporting-maintenance-v1',api.repo,anchor['branch']]))
    path='reports/'+role+'.json';item_at,blob_at=archive.fixed_reader(api,root)
    require(item_at(anchor['bootstrap_tree'],path) is None,'maintenance pre-bootstrap journal requires reviewed import')
    view={'mode':'archive','approval_path':str(Path(approval_path).resolve())}
    checkpoint=state.GitState(api,anchor['branch'],role,anchor['head'],bootstrap_existing=True,state_view=view)
    require(checkpoint.head==anchor['head'] and checkpoint.tree==anchor['tree'],'maintenance state changed before journal load')
    expected={'repository':api.repo,'stream':stream,'binding':binding}
    old=checkpoint.bytes;old_sha=None if old is None else state.git_hash(old)
    if old is None:
        journal=dict(expected,schema_version=1,interval_end=interval_end,previous_blob=None,previous_interval_end=None,
                     phase='backfill',remaining=0,review_blob=None,review_cursor=None,history_head=None,campaign=None,
                     page=1,offset=0,records_count=0,trust_sha256=trust_hash,policy_sha256=policy_hash,review_watch_count=0,review_watch_segments=0,source_epoch=0)
    else:
        journal=_journal(archive.document(old),expected)
        require(archive.instant(interval_end)>=archive.instant(journal['interval_end']),'maintenance cutoff cannot rewind')
        history=api.request(root+'/commits?sha='+anchor['head']+'&path='+quote(path,safe='')+'&per_page=1')
        require(type(history) is list and len(history)==1 and archive.state_paths.valid_hash(history[0].get('sha'),40),'maintenance publication missing')
        publication=api.request(root+'/git/commits/'+history[0]['sha'])
        require(publication.get('sha')==history[0]['sha'] and type(publication['parents']) is list and len(publication['parents'])==1,
                'maintenance publication identity differs')
        parent=api.request(root+'/git/commits/'+publication['parents'][0]['sha'])
        require(parent.get('sha')==publication['parents'][0]['sha'],'maintenance parent differs')
        archive._origin_ancestor(api.request,root,anchor['bootstrap_sha'],publication['sha'])
        archive._origin_ancestor(api.request,root,publication['sha'],anchor['head'])
        archive._origin_delta(api.request,root,parent['tree']['sha'],publication['tree']['sha'],path)
        before=blob_at(parent['tree']['sha'],path)
        require(blob_at(publication['tree']['sha'],path)==old and journal['previous_blob']==(None if before is None else state.git_hash(before)),
                'maintenance previous publication differs')
        require(journal['previous_interval_end']==(None if before is None else archive.document(before)['interval_end']),
                'maintenance previous interval differs')
    def persist(changed):
        changed=dict(changed,previous_blob=old_sha,previous_interval_end=None if old is None else journal['interval_end'])
        _journal(changed,expected)
        checkpoint.checkpoint(archive.canonical(changed))
        return dict(result,phase=changed['phase'])
    if old is None:return persist(journal)
    end=journal['interval_end'];result.update(phase=journal['phase'],interval_end=end)
    if journal['policy_sha256']!=policy_hash:
        return persist(dict(journal,phase='backfill',policy_sha256=policy_hash,trust_sha256=trust_hash,
                            history_head=None,campaign=None,page=1,offset=0,remaining=0,review_blob=None,review_cursor=None))
    if journal['trust_sha256']!=trust_hash:
        return persist(dict(journal,phase='backfill',trust_sha256=trust_hash,remaining=0,review_blob=None,review_cursor=None,history_head=None,campaign=None,page=1,offset=0))
    if acknowledge:
        require(journal['phase']=='verify' and end==interval_end and
                (journal['history_head'],journal['campaign'])==_operation[1:],
                'maintenance projection acknowledgement selector changed')
        return dict(persist(dict(journal,phase='ready')),status='projection-acknowledged')
    if journal['phase']=='verify' and (reporting or selecting):
        # Retry selectors are scheduling only: the reporting consumer must rerun
        # current coverage/projection before exact-selector acknowledgement.
        return dict(result,status='projection-ready',history_head=journal['history_head'],
                    campaign=journal['campaign'],interval_scoped=True)
    if journal['phase']=='verify':
        # Ordinary maintenance revisits source history after abandoned verification.
        return persist(dict(journal,phase='backfill',remaining=0,review_blob=None,review_cursor=None,
                            history_head=None,campaign=None,page=1,offset=0))
    scope=archive.interval_scope(anchor,stream,end,True)
    manifest_raw=blob_at(anchor['tree'],'receipt-archive/backfill/'+scope+'.json')
    watch_path='receipt-archive/progress/'+stream+'.json';watch_raw=blob_at(anchor['tree'],watch_path)
    watch=None if watch_raw is None else discovery.validate_checkpoint(archive.document(watch_raw),anchor,policy['receipts']['workflow_id'],archive.document(watch_raw)['pagination']['page_size'])
    if journal['phase']=='backfill':
        manifest=None if manifest_raw is None else archive.document(manifest_raw)
        complete=(manifest is not None and type(manifest.get('epoch')) is int and manifest['epoch']>journal['source_epoch']
                  and manifest['rounds_observed']==manifest['epoch'] and manifest['round_gaps']==manifest['last_round_gaps']==0
                  and manifest['stack']==[[int(archive.instant(anchor['coverage_from']).timestamp()),int(archive.instant(end).timestamp())]])
        if not complete or watch is None or not watch['scan']['complete']:
            discovery.backfill(source,api,policy,approval_path,stream,interval_end=end,page_size=100,tree_pages=10,interval_scoped=True)
            return result
        return persist(dict(journal,phase='review',source_epoch=manifest['epoch'],remaining=watch['watch']['count'],review_blob=None,review_cursor=None,review_watch_count=watch['watch']['count'],review_watch_segments=watch['watch']['segments']))
    if journal['phase']=='review':
        require(watch is not None,'maintenance watch history missing')
        remaining=journal['remaining']
        if watch['watch']['count']!=journal['review_watch_count'] or watch['watch']['segments']!=journal['review_watch_segments']:
            return persist(dict(journal,remaining=watch['watch']['count'],review_blob=None,review_cursor=None,
                                review_watch_count=watch['watch']['count'],review_watch_segments=watch['watch']['segments']))
        if journal['review_blob'] is not None and state.git_hash(watch_raw)!=journal['review_blob']:
            cursor=journal['review_cursor'];raw=blob_at(anchor['tree'],archive.state_paths.pending_segment_path(stream,cursor['segment']))
            require(raw is not None,'maintenance review segment missing')
            segment=discovery.validate_watch(archive.document(raw),api.repo,stream,cursor['segment'])
            size=len(segment['rows']);require(cursor['row']<size,'maintenance review row missing')
            current=watch['review'];visited=0
            if current['segment']==cursor['segment'] and cursor['row']<current['row']<size:
                visited=current['row']-cursor['row']
            elif current=={'segment':(cursor['segment']+1)%journal['review_watch_segments'],'row':0}:
                visited=size-cursor['row']
            # Credit actual protected cursor movement, including interrupted old
            # four-row work and a wrapped one-row watch. This schedules only;
            # coverage still independently checks every actual outcome.
            remaining=max(0,remaining-visited) if 1<=visited<=16 else watch['watch']['count']
        if watch['watch']['count']==0 or remaining==0:
            return persist(dict(journal,phase='checkpoint',remaining=0,review_blob=None,review_cursor=None))
        if journal['review_blob'] is None or state.git_hash(watch_raw)!=journal['review_blob']:
            return persist(dict(journal,remaining=remaining,review_blob=state.git_hash(watch_raw),review_cursor=watch['review']))
        discovery.reconcile(source,api,policy,trust_path,store,approval_path,stream,trust_mode=trust_mode,review_rows=16)
        return result
    if journal['phase']=='checkpoint':
        scoped='receipt-archive/projection/'+archive.projection_scope(api,anchor,policy,stream,end,True)+'.json'
        raw=blob_at(anchor['tree'],scoped)
        if raw is None or archive.document(raw)['next_segment']!=archive.document(raw)['records_count']:
            archive.checkpoint_projection(api,policy,trust_path,store,approval_path,stream,interval_end=end,limit=128,interval_scoped=True)
            return result
        lineage=archive.projection_lineage(api,policy,trust_path,store,approval_path,stream,interval_end=end,limit=1,interval_scoped=True)
        require(len(lineage['windows'])==1,'maintenance checked projection window missing')
        window=lineage['windows'][0]['checkpoint']
        campaign=archive.digest(archive.canonical(dict(window['binding'],frozen_head=window['frozen_head'],frozen_tree=window['frozen_tree'],trust_sha256=trust_hash)))
        return persist(dict(journal,phase='stage',history_head=lineage['history_head'],campaign=campaign,
                            records_count=window['records_count'],page=1,offset=0))
    if journal['phase']=='stage':
        lineage=archive.projection_lineage(api,policy,trust_path,store,approval_path,stream,interval_end=end,
                    history_head=journal['history_head'],page=journal['page'],limit=1,interval_scoped=True)
        require(len(lineage['windows'])==1,'maintenance required projection lineage gap')
        references=lineage['windows'][0]['checkpoint']['window']['references']
        if not references or journal['offset']>=len(references):
            return persist(dict(journal,phase='ready' if lineage['reaches_start'] else 'stage',page=journal['page']+1,offset=0))
        staged=archive.stage_projection(api,policy,trust_path,store,approval_path,stream,interval_end=end,
                    history_head=journal['history_head'],page=journal['page'],offset=journal['offset'],limit=8,interval_scoped=True)
        if staged['status'] in ('staged','already-staged'):
            require(type(staged.get('campaign')) is str and staged['campaign']==journal['campaign'], 'maintenance staged campaign differs')
            # The stage writer independently reconciles its actual ref before
            # returning. Reload after that publication; never use the stale
            # pre-stage base tree or overwrite another maintenance writer.
            checkpoint=state.GitState(api,anchor['branch'],role,anchor['head'],bootstrap_existing=True,state_view=view)
            require(checkpoint.bytes==old,'maintenance journal changed during stage publication')
            return persist(dict(journal,offset=journal['offset']+staged['facts_count']))
        return result
    # A delivered report cursor selects scheduling only. Existing coverage below
    # must still authenticate the old interval before an additive rollover.
    rollover=(reporting_cursor is not None and archive.instant(reporting_cursor)>=archive.instant(end)
              and archive.instant(interval_end)>archive.instant(end))
    if (reporting or selecting) and not rollover:
        needs_verification=reporting and (reporting_cursor is None or archive.instant(reporting_cursor)<archive.instant(end))
        prepared=persist(dict(journal,phase='verify')) if needs_verification else result
        return dict(prepared,status='projection-ready',history_head=journal['history_head'],
                    campaign=journal['campaign'],interval_scoped=True)
    coverage=discovery.coverage(source,api,policy,trust_path,store,approval_path,stream,interval_end=end,
                projection_end=end,history_head=journal['history_head'],campaign=journal['campaign'],interval_scoped=True)
    if not coverage['coverage_complete']:
        return dict(persist(dict(journal,phase='backfill',remaining=0,review_blob=None,review_cursor=None,history_head=None,campaign=None,page=1,offset=0)),gaps=coverage['gaps'])
    if archive.instant(interval_end)>archive.instant(end):
        return persist(dict(journal,interval_end=interval_end,source_epoch=0,phase='backfill',remaining=0,review_blob=None,review_cursor=None,
                            history_head=None,campaign=None,page=1,offset=0,records_count=0))
    return dict(result,status='ready',phase='ready',coverage_complete=True,history_head=journal['history_head'],
                campaign=journal['campaign'],interval_scoped=True)


def select_reporting(*args, reporting_cursor=None, **kwargs):
    """Validated scheduling selectors only; no verification intent or coverage."""
    require('_operation' not in kwargs, 'maintenance internal operation invalid')
    return maintain(*args, **kwargs, _operation=_SELECT_REPORTING if reporting_cursor is None else (_SELECT_REPORTING,reporting_cursor))


def prepare_reporting(*args, reporting_cursor=None, **kwargs):
    """Private pipeline scheduling only; this never certifies delivery coverage."""
    require('_operation' not in kwargs, 'maintenance internal operation invalid')
    return maintain(*args, **kwargs, _operation=_REPORTING if reporting_cursor is None else (_REPORTING,reporting_cursor))


def acknowledge_reporting(*args, history_head, campaign, **kwargs):
    """Acknowledge a successful private validator, with exact protected selectors."""
    require('_operation' not in kwargs, 'maintenance internal operation invalid')
    return maintain(*args, **kwargs, _operation=(_ACKNOWLEDGE,history_head,campaign))
