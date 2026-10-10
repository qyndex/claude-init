#!/usr/bin/env python3
"""Hosted reporting checkpoints on a data-only Git branch; no candidate execution."""
import argparse
import base64
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
import tempfile
from urllib.parse import quote
import uuid

spec = importlib.util.spec_from_file_location('slack', Path(__file__).with_name('factory-slack-digest.py'))
slack = importlib.util.module_from_spec(spec); spec.loader.exec_module(slack)
digest = slack.digest
require = digest.require
canonical = digest.canonical
TABLES = {
    'digest_cursors': ('stream', 'cutoff'),
    'digest_origins': ('stream', 'origin'),
    'digest_batches': ('key', 'stream', 'cutoff', 'payload', 'status', 'receipt'),
}
MAX_STATE = 8_000_000


def git_hash(blob):
    return hashlib.sha1(b'blob ' + str(len(blob)).encode() + b'\0' + blob).hexdigest()


class API:
    def __init__(self, repository, token):
        require(re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository or ''), 'state repository required')
        require(isinstance(token, str) and bool(token), 'state credential required')
        self.repo = repository; self.token = token

    def request(self, path, method='GET', payload=None):
        require(path == f'repos/{self.repo}' or path.startswith(f'repos/{self.repo}/'), 'foreign state API path')
        env = dict(os.environ); env['GH_TOKEN'] = self.token
        command = ['gh', 'api', '--hostname', 'github.com', '--method', method, path]
        if payload is not None:
            command += ['--input', '-']
        result = subprocess.run(command, input=canonical(payload).encode() if payload is not None else None,
                                env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
        require(result.returncode == 0, 'state API failed; reconcile authoritative branch before retry')
        require(len(result.stdout) <= MAX_STATE * 2, 'state API response too large')
        return json.loads(result.stdout, object_pairs_hook=digest.coordinator.contract.no_duplicate_keys)


POLICY_FIELDS = {'id', 'name', 'target', 'source_type', 'source', 'enforcement',
                 'conditions', 'rules', 'node_id', 'created_at', 'updated_at'}


def policy_projection(policy):
    require(POLICY_FIELDS <= set(policy), 'state policy metadata incomplete')
    projection = {key: policy[key] for key in POLICY_FIELDS}
    for key in ('created_at', 'updated_at'):
        projection[key] = digest.stamp(digest.instant(projection[key]))
    return projection


def attest_policy(api, identity, now=None):
    now = now or datetime.now(timezone.utc)
    policy = api.request(f'repos/{api.repo}/rulesets/{identity}')
    require(policy.get('id') == identity and policy.get('source_type') == 'Repository' and
            policy.get('source') == api.repo and policy.get('target') == 'branch' and
            policy.get('enforcement') == 'active' and policy.get('bypass_actors') == [],
            'operator must observe an active repository policy with an explicit empty bypass list')
    projection = policy_projection(policy)
    updated = digest.instant(projection['updated_at'])
    # Observe after the timestamp has settled; subsequent server-side changes invalidate approval.
    require((now - updated).total_seconds() >= 60, 'state policy must settle for 60 seconds before approval')
    return {'schema_version': 1, 'repository': api.repo, 'ruleset_id': identity,
            'policy_sha256': hashlib.sha256(canonical(projection).encode()).hexdigest(),
            'policy_updated_at': projection['updated_at'], 'observed_at': digest.stamp(now),
            'bypass_actors': []}


def verify_policy(policy, repository, identity, approvals=None, now=None):
    require(policy.get('enforcement') == 'active', 'state protection disabled or bypassable')
    if 'bypass_actors' in policy:
        require(policy['bypass_actors'] == [], 'state protection disabled or bypassable')
        return
    require(isinstance(approvals, dict) and str(identity) in approvals,
            'state bypass actors hidden; protected operator approval required')
    approval = approvals[str(identity)]
    require(isinstance(approval, dict) and set(approval) == {'schema_version', 'repository',
            'ruleset_id', 'policy_sha256', 'policy_updated_at', 'observed_at', 'bypass_actors'} and
            type(approval['schema_version']) is int and approval['schema_version'] == 1 and
            approval['repository'] == repository and type(approval['ruleset_id']) is int and
            approval['ruleset_id'] == identity and approval['bypass_actors'] == [],
            'state policy approval missing or mismatched')
    projection = policy_projection(policy)
    require(projection['id'] == identity and projection['target'] == 'branch' and
            projection['source_type'] == 'Repository' and projection['source'] == repository and
            approval['policy_updated_at'] == projection['updated_at'] and
            approval['policy_sha256'] == hashlib.sha256(canonical(projection).encode()).hexdigest(),
            'state policy changed since operator approval')
    observed = digest.instant(approval['observed_at'])
    updated = digest.instant(projection['updated_at'])
    require((observed - updated).total_seconds() >= 60 and observed <= (now or datetime.now(timezone.utc)),
            'state policy approval clock invalid')


class GitState:
    def __init__(self, api, branch, stream, bootstrap_sha=None, policy_approvals=None):
        require(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._/-]*', branch or '') and '..' not in branch and not branch.endswith('/'), 'state branch invalid')
        require(digest.coordinator.contract.digest(stream, 64), 'state stream invalid')
        self.api = api; self.root = f'repos/{api.repo}'; self.branch = branch
        repo = api.request(self.root)
        require(repo['full_name'] == api.repo and repo['archived'] is False and branch != repo['default_branch'], 'state cannot use default branch or archived repo')
        self.private = repo['private']
        rules = api.request(self.root + '/rules/branches/' + quote(branch, safe=''))
        require({'non_fast_forward', 'deletion'} <= {rule['type'] for rule in rules}, 'state branch rewrite/deletion protection missing')
        ids = {rule['ruleset_id'] for rule in rules if 'ruleset_id' in rule}
        require(bool(ids), 'state protection provenance missing')
        for identity in ids:
            policy = api.request(self.root + '/rulesets/' + str(identity))
            verify_policy(policy, api.repo, identity, policy_approvals)
        ref = api.request(self.root + '/git/ref/heads/' + quote(branch, safe=''))
        require(ref['ref'] == 'refs/heads/' + branch and ref['object']['type'] == 'commit', 'state reference differs')
        self.head = ref['object']['sha']; require(digest.coordinator.contract.digest(self.head, 40), 'state commit invalid')
        commit = api.request(self.root + '/git/commits/' + self.head)
        require(commit['sha'] == self.head, 'state commit differs')
        self.tree = commit['tree']['sha']
        tree = api.request(self.root + '/git/trees/' + self.tree + '?recursive=1')
        require(tree.get('truncated') is False, 'state tree incomplete')
        self.path = 'reports/' + stream + '.json'
        # Data-only branch: no workflows, executables or source files can be imported.
        require(all(item['type'] == 'tree' or (item['type'] == 'blob' and item['mode'] == '100644' and (item['path'] == 'README.md' or re.fullmatch(r'reports/[0-9a-f]{64}\.json', item['path']))) for item in tree['tree']), 'state branch contains unexpected paths or modes')
        entries = [item for item in tree['tree'] if item['path'] == self.path]
        require(len(entries) <= 1, 'state path ambiguous')
        self.bytes = None
        if entries:
            item = entries[0]
            require(0 < item['size'] <= MAX_STATE, 'checkpoint size invalid')
            blob = api.request(self.root + '/git/blobs/' + item['sha'])
            require(blob['encoding'] == 'base64' and blob['sha'] == item['sha'], 'checkpoint encoding/identity differs')
            self.bytes = base64.b64decode(''.join(blob['content'].split()), validate=True)
            require(len(self.bytes) == blob['size'] == item['size'] and git_hash(self.bytes) == item['sha'], 'checkpoint bytes differ')
        else:
            require(bootstrap_sha == self.head and not any(item['path'].startswith('reports/') for item in tree['tree']), 'missing checkpoint requires exact empty bootstrap revision; never reset silently')

    def checkpoint(self, data):
        require(isinstance(data, bytes) and 0 < len(data) <= MAX_STATE, 'checkpoint too large')
        if data == self.bytes:
            return
        blob = self.api.request(self.root + '/git/blobs', 'POST', {'encoding': 'base64', 'content': base64.b64encode(data).decode()})
        require(blob['sha'] == git_hash(data), 'uploaded checkpoint differs')
        tree = self.api.request(self.root + '/git/trees', 'POST', {'base_tree': self.tree, 'tree': [{'path': self.path, 'mode': '100644', 'type': 'blob', 'sha': blob['sha']}]})
        # A unique commit prevents two identical writers producing the same SHA and both passing fast-forward.
        commit = self.api.request(self.root + '/git/commits', 'POST', {'message': 'factory: reporting checkpoint ' + uuid.uuid4().hex, 'tree': tree['sha'], 'parents': [self.head]})
        require(commit['tree']['sha'] == tree['sha'] and [p['sha'] for p in commit['parents']] == [self.head], 'checkpoint ancestry differs')
        require(digest.coordinator.contract.digest(commit['sha'], 40), 'checkpoint commit invalid')
        result = self.api.request(self.root + '/git/refs/heads/' + quote(self.branch, safe=''), 'PATCH', {'sha': commit['sha'], 'force': False})
        require(result['ref'] == 'refs/heads/' + self.branch and result['object']['sha'] == commit['sha'], 'checkpoint reference differs')
        self.head = commit['sha']; self.tree = tree['sha']; self.bytes = data


def snapshot(path, repository, stream, destination, branch):
    with sqlite3.connect(path) as db:
        db.row_factory = sqlite3.Row
        tables = {table: [dict(row) for row in db.execute(f'SELECT {",".join(columns)} FROM {table} ORDER BY {columns[0]}')] for table, columns in TABLES.items()}
    document = {'schema_version': 1, 'repository': repository, 'stream': stream, 'destination': destination, 'branch': branch, 'tables': tables}
    validate(document, repository, stream)
    return canonical(document).encode()


def validate(document, repository, stream):
    require(set(document) == {'schema_version', 'repository', 'stream', 'destination', 'branch', 'tables'} and type(document['schema_version']) is int and document['schema_version'] == 1 and document['repository'] == repository and document['stream'] == stream, 'foreign checkpoint schema/identity')
    require(stream == hashlib.sha256(canonical([repository, document['destination'], document['branch']]).encode()).hexdigest(), 'checkpoint destination/branch differs')
    require(set(document['tables']) == set(TABLES), 'unexpected checkpoint tables')
    for table, columns in TABLES.items():
        rows = document['tables'][table]
        require(isinstance(rows, list) and all(isinstance(row, dict) and set(row) == set(columns) and row['stream'] == stream for row in rows), 'malformed checkpoint rows')
        require(len({row[columns[0]] for row in rows}) == len(rows), 'duplicate checkpoint rows')
    require(len(document['tables']['digest_cursors']) == len(document['tables']['digest_origins']) == 1, 'checkpoint cursor/origin missing')
    require(isinstance(document['tables']['digest_cursors'][0]['cutoff'], str) and isinstance(document['tables']['digest_origins'][0]['origin'], str), 'checkpoint timestamps invalid')
    cursor = digest.instant(document['tables']['digest_cursors'][0]['cutoff'])
    origin = digest.instant(document['tables']['digest_origins'][0]['origin'])
    require(origin <= cursor, 'checkpoint origin after cursor')
    pending = 0; confirmed = []
    for row in document['tables']['digest_batches']:
        require(all(isinstance(row[key], str) for key in ('key','cutoff','payload','status')), 'batch fields invalid')
        require(row['status'] in {'pending', 'uncertain', 'confirmed'}, 'invalid batch state')
        payload = json.loads(row['payload'], object_pairs_hook=digest.coordinator.contract.no_duplicate_keys)
        require(set(payload) == {'schema_version','repository','destination','from','until','timezone','display_from','display_until','merges','product_acceptance'} and payload['schema_version'] == 1, 'unexpected report fields')
        require(payload['destination'] == document['destination'] and origin <= digest.instant(payload['from']) < digest.instant(payload['until']), 'report interval/destination differs')
        for item in payload['merges']:
            require(set(item) == {'pr','title','url','merge_sha','merged_at','late_discovered','delivery_evidence','evidence_status','merge_time_checks'}, 'unexpected merge fields')
            require(type(item['pr']) is int and item['pr'] > 0 and item['url'] == f'https://github.com/{repository}/pull/{item["pr"]}', 'report PR source differs')
            require(all(set(proof) == {'task','spec','revision','producer_run','artifact_digest'} for proof in item['delivery_evidence']), 'unexpected evidence fields')
        require(payload['repository'] == repository and payload['until'] == row['cutoff'], 'checkpoint report differs')
        require(row['key'] == hashlib.sha256(canonical([stream, digest.stamp(digest.instant(payload['from'])), digest.stamp(digest.instant(payload['until']))]).encode()).hexdigest(), 'checkpoint report key differs')
        if row['status'] == 'confirmed':
            receipt = json.loads(row['receipt'])
            require(set(receipt) == {'key', 'payload_sha256', 'destination', 'message_id'} and receipt['key'] == row['key'] and receipt['payload_sha256'] == hashlib.sha256(row['payload'].encode()).hexdigest() and receipt['destination'] == payload['destination'] and isinstance(receipt['message_id'], str) and bool(receipt['message_id']), 'checkpoint receipt differs')
            confirmed.append(digest.instant(row['cutoff']))
            require(digest.instant(row['cutoff']) <= cursor, 'confirmed report beyond cursor')
        else:
            pending += 1
            require(row['receipt'] is None and digest.instant(row['cutoff']) > cursor, 'pending receipt/cutoff differs')
    require(cursor == (max(confirmed) if confirmed else origin), 'cursor lacks confirmed delivery')
    require(pending <= 1, 'multiple pending reports')


class HostedDigest(digest.Digest):
    def __init__(self, path, config, state):
        self.state = state; self.failed = False
        # A private local projection is reconstructed from typed JSON, never remote SQL/SQLite binaries.
        digest.Digest(path, config['repository'], config['destination'], config['start'], config['branch'])
        if state.bytes is not None:
            document = json.loads(state.bytes, object_pairs_hook=digest.coordinator.contract.no_duplicate_keys)
            stream = hashlib.sha256(canonical([config['repository'], config['destination'], config['branch']]).encode()).hexdigest()
            validate(document, config['repository'], stream)
            with sqlite3.connect(path) as db:
                for table, columns in TABLES.items():
                    db.execute(f'DELETE FROM {table}')
                    for row in document['tables'][table]:
                        db.execute(f'INSERT INTO {table}({",".join(columns)}) VALUES({",".join("?" for _ in columns)})', [row[c] for c in columns])
        super().__init__(path, config['repository'], config['destination'], config['start'], config['branch'])

    @contextmanager
    def transaction(self):
        require(not self.failed, 'failed checkpoint requires a fresh authoritative restore')
        with super().transaction() as db:
            yield db
        # Every state change must become durable BEFORE caller can send or acknowledge delivery.
        try:
            self.state.checkpoint(snapshot(self.path, self.repository, self.stream, self.destination, self.branch))
        except BaseException:
            self.failed = True; raise


def run(config, report_api, state_api, slack_client, path, now):
    require(config.get('enabled') is True and report_api.repo == config['repository'], 'hosted reporting disabled/foreign')
    source = report_api.get(f'repos/{report_api.repo}')
    require(source['full_name'] == report_api.repo and source['default_branch'] == config['branch'], 'report repository/default branch differs')
    stream = hashlib.sha256(canonical([config['repository'], config['destination'], config['branch']]).encode()).hexdigest()
    state = GitState(state_api, config['state_branch'], stream, config.get('bootstrap_sha'), config.get('policy_approvals'))
    require(not source['private'] or state.private, 'private repository cannot publish public checkpoints')
    store = HostedDigest(path, config, state)
    target = slack.due(now)
    if digest.instant(store.cursor()) >= digest.instant(target):
        return {'status': 'not-due'}
    batch = store.prepare(report_api, target)
    transport = slack.Slack(slack_client, config['team_id'], config['destination'], batch['key'], batch['payload'])
    receipt = store.deliver(batch['key'], transport)
    require(transport.lookup(batch['key']).get('receipt') == receipt, 'Delivered receipt not visible in Slack history; preserve confirmed state')
    return {'status': 'delivered', 'receipt': receipt, 'checkpoint_sha': state.head}


def main():
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--config', type=Path, required=True)
    args = parser.parse_args(); config = digest.coordinator.contract.load(args.config)
    require(os.environ.get('GITHUB_SERVER_URL') == 'https://github.com', 'hosted state supports github.com only')
    require(os.environ.get('GITHUB_REPOSITORY') == config['repository'] and os.environ.get('GITHUB_REF') == 'refs/heads/' + config['branch'], 'hosted reporting requires target default branch')
    os.umask(0o077)
    state_api = API(config['state_repository'], os.environ.get('FACTORY_REPORTING_STATE_TOKEN') or os.environ.get('GH_TOKEN'))
    with tempfile.TemporaryDirectory(prefix='factory-reporting-') as tmp:
        result = run(config, digest.coordinator.GitHub(config['repository']), state_api, slack.SlackHTTP(), Path(tmp)/'reporting.sqlite', datetime.now(timezone.utc))
    print(json.dumps(result))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError, sqlite3.Error, subprocess.SubprocessError) as error:
        public = {'state bypass actors hidden; protected operator approval required',
                  'state policy approval missing or mismatched', 'state policy changed since operator approval',
                  'state policy approval clock invalid', 'state policy metadata incomplete',
                  'state protection disabled or bypassable'}
        detail = str(error) if str(error) in public else 'reconcile authoritative state before retry'
        print('Hosted reporting blocked: ' + detail, file=sys.stderr); sys.exit(1)
