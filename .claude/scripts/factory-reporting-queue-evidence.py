#!/usr/bin/env python3
"""Bounded administrative run observations; no live rollout or Slack authority."""
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote
import hashlib
import importlib.util
import json
import os
import re
import subprocess

LIMIT = 2 * 1024 * 1024
TOTAL = 32 * 1024 * 1024
WORKFLOW = '.github/workflows/factory-reporting-queue.yml'
STEP = 'Observe and reconcile protected queue notifications'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def pairs(items):
    result = {}
    for key, value in items:
        require(key not in result, 'queue evidence duplicate JSON field'); result[key] = value
    return result


def decode(raw):
    require(type(raw) is bytes and len(raw) <= LIMIT, 'queue evidence response bound exceeded')
    try:
        return json.loads(raw, object_pairs_hook=pairs)
    except (ValueError, UnicodeError, RecursionError) as error:
        raise ValueError('queue evidence JSON invalid') from error


def integer(value):
    return type(value) is int and 0 < value < 2**63


def instant(value):
    require(type(value) is str and len(value) <= 40 and re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})', value) is not None, 'queue evidence timestamp invalid')
    require(value.endswith('Z') or (int(value[-5:-3]) < 24 and int(value[-2:]) < 60), 'queue evidence timestamp offset invalid')
    try:
        return datetime.fromisoformat(value.replace('Z','+00:00')).astimezone(timezone.utc)
    except (ValueError, OverflowError) as error:
        raise ValueError('queue evidence timestamp invalid') from error


class GitHub:
    """Existing gh authentication, fixed-host GET, bounded during pipe reads."""
    def __init__(self, repository):
        require(type(repository) is str and len(repository) <= 201 and re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository) is not None and all(part not in {'.','..'} for part in repository.split('/')), 'queue evidence repository invalid')
        self.repo = repository; self.calls = self.consumed = 0
        spec = importlib.util.spec_from_file_location('queue_evidence_process', Path(__file__).with_name('factory-bounded-process.py'))
        self.process = importlib.util.module_from_spec(spec); spec.loader.exec_module(self.process)
    def request(self, path, method='GET', payload=None, *, raw=False):
        require(method == 'GET' and payload is None and type(raw) is bool, 'queue evidence API is read only')
        require(type(path) is str and (path == 'repos/'+self.repo or path.startswith('repos/'+self.repo+'/')) and re.fullmatch(r'[A-Za-z0-9_./?=&%+-]+', path) is not None and '%' not in path.replace('%2F','') and all(part not in {'.','..'} for part in path.split('?',1)[0].split('/')), 'queue evidence foreign API endpoint')
        require(self.calls < 128 and self.consumed < TOTAL, 'queue evidence API budget exhausted'); self.calls += 1
        # Do not forward Slack/state-writer credentials to the read-only gh child.
        env = {key:value for key,value in os.environ.items() if key in {'PATH','HOME','GH_CONFIG_DIR','XDG_CONFIG_HOME','GH_TOKEN','GITHUB_TOKEN','SSL_CERT_FILE','SSL_CERT_DIR','TMPDIR'}}
        result = self.process.run(['gh','api','--hostname','github.com','--method','GET',path], env=env, cwd=str(Path.cwd()), timeout=30, limit=LIMIT, aggregate_limit=min(LIMIT,TOTAL-self.consumed))
        self.consumed += len(result.stdout)+len(result.stderr)
        require(result.returncode == 0 and self.consumed <= TOTAL, 'queue evidence API unavailable or budget exhausted')
        return result.stdout if raw else decode(result.stdout)


def checkout(root):
    root = Path(root).resolve()
    def git(*args):
        try:
            return subprocess.run(['git','-C',str(root),*args], capture_output=True, text=True, timeout=10, check=True).stdout.strip()
        except (OSError, subprocess.SubprocessError) as error:
            raise ValueError('queue evidence reviewed checkout unavailable') from error
    require(git('rev-parse','--show-toplevel') == str(root), 'queue evidence checkout root differs')
    require(not git('status','--porcelain','--untracked-files=normal','--','.claude/scripts',WORKFLOW), 'queue evidence source checkout is dirty')
    git('ls-files','--error-unmatch',WORKFLOW,'.claude/scripts/factory-reporting-queue.py')
    sha = git('rev-parse','--verify','HEAD'); require(re.fullmatch(r'[0-9a-f]{40}',sha) is not None, 'queue evidence checkout SHA invalid')
    return sha


def results(raw):
    require(type(raw) is bytes and len(raw) <= LIMIT, 'queue evidence selected log bound exceeded')
    try:
        lines = raw.decode('utf-8').splitlines()
    except UnicodeError as error:
        raise ValueError('queue evidence selected log encoding invalid') from error
    selected = []
    for line in lines:
        prefix = re.match(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z ', line)
        line = line[prefix.end():] if prefix else line
        if not line.startswith(('{','[')):
            continue
        require(prefix is not None, 'queue evidence result lacks server log prefix')
        require(len(line) <= 4096, 'queue evidence result bound exceeded')
        item = decode(line.encode())
        require(type(item) is dict and set(item) == {'notifications','reconciled'} and all(type(value) is int and 0 <= value <= 1000 for value in item.values()), 'queue evidence safe result differs')
        selected.append(item); require(len(selected) <= 2, 'queue evidence extra result matches')
    return selected


def observe_runs(api, root, branch, selections, now):
    """Actual reads required; API injection is an offline test seam, not CLI input."""
    require(type(branch) is str and len(branch) <= 255 and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._/-]*',branch) is not None and '..' not in branch and not branch.endswith('/'), 'queue evidence branch invalid')
    require(type(selections) is dict and set(selections) == {'drill','recovery','repeat'}, 'queue evidence run selectors differ')
    ids = set()
    for item in selections.values():
        require(type(item) is dict and set(item) == {'run_id','attempt'} and all(integer(value) for value in item.values()), 'queue evidence run selector invalid')
        require(item['run_id'] not in ids, 'queue evidence run selectors repeat'); ids.add(item['run_id'])
    require(isinstance(now,datetime) and now.tzinfo is not None and now.utcoffset() is not None and now.astimezone(timezone.utc) <= datetime.now(timezone.utc), 'queue evidence observation clock invalid')
    sha = checkout(root); prefix = 'repos/'+api.repo
    repository = api.request(prefix)
    require(type(repository) is dict and integer(repository.get('id')) and repository.get('full_name') == api.repo and repository.get('default_branch') == branch and repository.get('archived') is False and type(repository.get('private')) is bool, 'queue evidence repository differs')
    refpath = prefix+'/git/ref/heads/'+quote(branch,safe='')
    def source():
        ref = api.request(refpath)
        require(type(ref) is dict and ref.get('ref') == 'refs/heads/'+branch and type(ref.get('object')) is dict and ref['object'].get('type') == 'commit' and ref['object'].get('sha') == sha, 'queue evidence current main source differs')
    source(); workflow = api.request(prefix+'/actions/workflows/factory-reporting-queue.yml')
    require(type(workflow) is dict and integer(workflow.get('id')) and workflow.get('path') == WORKFLOW and workflow.get('state') == 'active', 'queue evidence workflow differs')
    observed = []; previous = None
    for role, counts in (('drill',[1,0]),('recovery',[1]),('repeat',[0])):
        selector = selections[role]; run = api.request(prefix+'/actions/runs/'+str(selector['run_id']))
        require(type(run) is dict and all(integer(run.get(key)) for key in ('id','workflow_id','run_attempt')) and run['id'] == selector['run_id'] and run['run_attempt'] == selector['attempt'] and run['workflow_id'] == workflow['id'], 'queue evidence actual run identity differs')
        allowed = ('workflow_dispatch',) if role == 'drill' else ('workflow_dispatch','schedule')
        require(run.get('path') == WORKFLOW and run.get('head_branch') == branch and run.get('head_sha') == sha and run.get('event') in allowed, 'queue evidence protected run source differs')
        require(run.get('status') == 'completed' and run.get('conclusion') == 'success' and all(type(run.get(key)) is dict and integer(run[key].get('id')) and run[key]['id'] == repository['id'] and run[key].get('full_name') == api.repo for key in ('repository','head_repository')), 'queue evidence run result or repository differs')
        created, started, ended = (instant(run.get(key)) for key in ('created_at','run_started_at','updated_at'))
        require(created <= started <= ended <= now and (previous is None or previous <= started), 'queue evidence run windows overlap or invalid'); previous = ended
        jobs = api.request(prefix+'/actions/runs/'+str(run['id'])+'/attempts/'+str(run['run_attempt'])+'/jobs?per_page=100&page=1')
        require(type(jobs) is dict and type(jobs.get('total_count')) is int and jobs['total_count'] == 1 and type(jobs.get('jobs')) is list and len(jobs['jobs']) == 1, 'queue evidence jobs incomplete or ambiguous')
        job = jobs['jobs'][0]
        require(type(job) is dict and integer(job.get('id')) and integer(job.get('run_id')) and job['run_id'] == run['id'] and integer(job.get('run_attempt')) and job['run_attempt'] == run['run_attempt'] and job.get('head_sha') == sha and job.get('name') == 'monitor' and job.get('status') == 'completed' and job.get('conclusion') == 'success', 'queue evidence monitor job differs')
        steps = job.get('steps'); require(type(steps) is list and 0 < len(steps) <= 32 and all(type(step) is dict and integer(step.get('number')) for step in steps) and len({step['number'] for step in steps}) == len(steps), 'queue evidence job steps invalid')
        selected = [step for step in steps if step.get('name') == STEP]
        require(len(selected) == 1 and selected[0].get('status') == 'completed' and selected[0].get('conclusion') == 'success', 'queue evidence monitor step differs')
        raw = api.request(prefix+'/actions/jobs/'+str(job['id'])+'/logs', raw=True)
        safe = results(raw); require([item['notifications'] for item in safe] == counts, 'queue evidence fresh CLI results differ')
        observed.append({'role':role,'run_id':run['id'],'attempt':run['run_attempt'],'job_id':job['id'],'started_at':started.isoformat(),'ended_at':ended.isoformat(),'notifications':counts,'log_sha256':hashlib.sha256(raw).hexdigest()})
    source()
    return {'mode':'administrative-run-observation','repository':api.repo,'source_sha':sha,'runs':observed}
