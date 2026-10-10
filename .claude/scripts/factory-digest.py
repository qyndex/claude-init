#!/usr/bin/env python3
"""Durable merge digest core; live delivery requires a trusted transport adapter."""
import argparse
from contextlib import contextmanager
from datetime import datetime, time, timezone
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sqlite3
from zoneinfo import ZoneInfo

spec = importlib.util.spec_from_file_location('coordinator', Path(__file__).with_name('factory-coordinator.py'))
coordinator = importlib.util.module_from_spec(spec); spec.loader.exec_module(coordinator)
require = coordinator.require
SYDNEY = ZoneInfo('Australia/Sydney')


def instant(value):
    parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    require(parsed.tzinfo is not None, 'timezone required')
    return parsed.astimezone(timezone.utc)


def stamp(value):
    return value.astimezone(timezone.utc).isoformat()


def cutoff(day):
    return stamp(datetime.combine(datetime.fromisoformat(day).date(), time(8), SYDNEY))


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False)


class Digest:
    def __init__(self, path, repository, destination, start, branch='main'):
        require(repository.count('/') == 1 and bool(destination) and bool(branch), 'report configuration required')
        self.path = str(Path(path).resolve())
        self.repository = repository; self.destination = destination; self.branch = branch
        self.stream = hashlib.sha256(canonical([repository, destination, branch]).encode()).hexdigest()
        with self.transaction() as db:
            db.execute('CREATE TABLE IF NOT EXISTS digest_cursors(stream TEXT PRIMARY KEY, cutoff TEXT NOT NULL)')
            db.execute('CREATE TABLE IF NOT EXISTS digest_batches(key TEXT PRIMARY KEY,stream TEXT NOT NULL,cutoff TEXT NOT NULL,payload TEXT NOT NULL,status TEXT NOT NULL,receipt TEXT)')
            db.execute('INSERT OR IGNORE INTO digest_cursors VALUES(?,?)', (self.stream, stamp(instant(start))))
            db.execute('CREATE TABLE IF NOT EXISTS digest_origins(stream TEXT PRIMARY KEY, origin TEXT NOT NULL)')
            if db.execute('SELECT origin FROM digest_origins WHERE stream=?', (self.stream,)).fetchone() is None:
                first = db.execute('SELECT payload FROM digest_batches WHERE stream=? ORDER BY cutoff LIMIT 1', (self.stream,)).fetchone()
                original = json.loads(first['payload'])['from'] if first else db.execute('SELECT cutoff FROM digest_cursors WHERE stream=?', (self.stream,)).fetchone()[0]
                db.execute('INSERT INTO digest_origins VALUES(?,?)', (self.stream, stamp(instant(original))))

    @contextmanager
    def transaction(self):
        db = sqlite3.connect(self.path, timeout=30, isolation_level=None)
        db.row_factory = sqlite3.Row
        db.execute('BEGIN IMMEDIATE')
        try:
            yield db
            db.execute('COMMIT')
        except BaseException:
            db.execute('ROLLBACK'); raise
        finally:
            db.close()

    def cursor(self):
        with self.transaction() as db:
            return db.execute('SELECT cutoff FROM digest_cursors WHERE stream=?', (self.stream,)).fetchone()[0]

    def batch(self, key):
        with self.transaction() as db:
            row = db.execute('SELECT * FROM digest_batches WHERE key=? AND stream=?', (key, self.stream)).fetchone()
            require(row is not None, 'unknown report')
            return dict(row)

    def prepare(self, api, until):
        require(api.repo == self.repository, 'foreign report source')
        end = instant(until)
        require(end <= datetime.now(timezone.utc), 'future cutoff cannot be delivered')
        with self.transaction() as db:
            pending = db.execute("SELECT * FROM digest_batches WHERE stream=? AND status!='confirmed'", (self.stream,)).fetchone()
            if pending:
                return dict(pending)
            start = instant(db.execute('SELECT cutoff FROM digest_cursors WHERE stream=?', (self.stream,)).fetchone()[0])
            require(end > start, 'cutoff must advance')
            origin = instant(db.execute('SELECT origin FROM digest_origins WHERE stream=?', (self.stream,)).fetchone()[0])
            require(origin <= start, 'reporting origin exceeds cursor')
            reported = {}
            for previous in db.execute("SELECT key,payload,receipt FROM digest_batches WHERE stream=? AND status='confirmed'", (self.stream,)):
                remote = json.loads(previous['receipt'])
                require(remote['key'] == previous['key'] and remote['destination'] == self.destination and remote['payload_sha256'] == hashlib.sha256(previous['payload'].encode()).hexdigest(), 'historical report bytes differ from delivery receipt')
                document = json.loads(previous['payload'])
                require(document['repository'] == self.repository and document['destination'] == self.destination, 'foreign report history')
                for item in document['merges']:
                    require(type(item['pr']) is int and item['pr'] > 0 and coordinator.contract.digest(item['merge_sha'], 40), 'invalid historical merge')
                    require(item['pr'] not in reported or reported[item['pr']] == item['merge_sha'], 'contradictory report history')
                    reported[item['pr']] = item['merge_sha']
            # REST pagination is completed before any cursor/report state is committed.
            pages = api.request(f'repos/{self.repository}/pulls?state=closed&per_page=100', paginate=True)
            merged = {}
            for page in pages:
                require(isinstance(page, list), 'invalid merge page')
                for pr in page:
                    if not pr.get('merged_at') or pr['base']['ref'] != self.branch:
                        continue
                    at = instant(pr['merged_at'])
                    if not origin < at <= end:
                        continue
                    require(pr['base']['repo']['full_name'] == self.repository and type(pr['number']) is int and pr['number'] > 0, 'foreign merge')
                    require(coordinator.contract.digest(pr['merge_commit_sha'], 40), 'missing merge identity')
                    if pr['number'] in reported:
                        require(reported[pr['number']] == pr['merge_commit_sha'], 'actual merge contradicts delivered coverage')
                        continue
                    old = merged.get(pr['number'])
                    require(old is None or old == pr, 'inconsistent merge pages')
                    merged[pr['number']] = pr
            tables = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            proofs = []
            if {'delivery_receipts', 'delivery_provenance'} <= tables:
                proofs = db.execute('SELECT r.*,p.provenance FROM delivery_receipts r JOIN delivery_provenance p ON r.task=p.task').fetchall()
            entries = []
            for pr in sorted(merged.values(), key=lambda p: (instant(p['merged_at']), p['number'])):
                matches = []
                for proof in proofs:
                    delivered = json.loads(proof['receipt']); provenance = json.loads(proof['provenance'])
                    receipt = provenance['receipt']
                    if delivered.get('repository') == self.repository and delivered.get('pr') == pr['number']:
                        require(receipt['repository'] == self.repository and receipt['pull_request'] == pr['number'] and receipt['merged'] is True and receipt['eligible'] is True, 'foreign delivery provenance')
                        require(type(provenance['run_id']) is int and provenance['run_id'] > 0 and provenance['artifact_digest'].startswith('sha256:') and coordinator.contract.digest(provenance['artifact_digest'][7:], 64), 'invalid delivery provenance')
                        require(delivered['merge_sha'] == pr['merge_commit_sha'] == receipt['merge_sha'], 'delivery merge conflicts')
                        require(receipt['head_sha'] == pr['head']['sha'] and receipt['spec_sha256'] == proof['revision'] and proof['task'] in receipt['task_ids'], 'delivery provenance conflicts')
                        matches.append({'task': proof['task'], 'spec': receipt['spec'], 'revision': proof['revision'],
                                        'producer_run': provenance['run_id'], 'artifact_digest': provenance['artifact_digest']})
                entries.append({'pr': pr['number'], 'title': pr['title'], 'url': pr['html_url'], 'merge_sha': pr['merge_commit_sha'],
                                'merged_at': stamp(instant(pr['merged_at'])), 'late_discovered': instant(pr['merged_at']) <= start, 'delivery_evidence': matches,
                                'evidence_status': 'authenticated' if matches else 'missing', 'merge_time_checks': 'not independently recorded'})
            payload = canonical({'schema_version': 1, 'repository': self.repository, 'destination': self.destination,
                                 'from': stamp(start), 'until': stamp(end), 'timezone': 'Australia/Sydney',
                                 'display_from': start.astimezone(SYDNEY).isoformat(), 'display_until': end.astimezone(SYDNEY).isoformat(),
                                 'merges': entries, 'product_acceptance': 'not inferred from merge'})
            key = hashlib.sha256(canonical([self.stream, stamp(start), stamp(end)]).encode()).hexdigest()
            db.execute('INSERT INTO digest_batches VALUES(?,?,?,?,?,NULL)', (key, self.stream, stamp(end), payload, 'pending'))
            return dict(db.execute('SELECT * FROM digest_batches WHERE key=?', (key,)).fetchone())

    def receipt(self, row, receipt):
        require(isinstance(receipt, dict) and set(receipt) == {'key', 'payload_sha256', 'destination', 'message_id'}, 'malformed remote receipt')
        require(receipt['key'] == row['key'] and receipt['destination'] == self.destination and
                receipt['payload_sha256'] == hashlib.sha256(row['payload'].encode()).hexdigest() and
                isinstance(receipt['message_id'], str) and bool(receipt['message_id']), 'remote delivery differs')
        return canonical(receipt)

    def deliver(self, key, transport):
        # Independent processes cannot send/reconcile this stream concurrently.
        fd = os.open(self.path + '.' + self.stream + '.delivery-lock', os.O_CREAT | os.O_RDWR, 0o600)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            row = self.batch(key)
            if row['status'] == 'confirmed':
                return json.loads(row['receipt'])
            if row['status'] == 'uncertain':
                lookup = transport.lookup(key)
                require(isinstance(lookup, dict), 'invalid remote lookup')
                if lookup.get('receipt') is not None:
                    return self.confirm(row, lookup['receipt'])
                require(lookup == {'receipt': None, 'authoritative_absence': True}, 'remote delivery remains uncertain')
                with self.transaction() as db:
                    db.execute("UPDATE digest_batches SET status='pending' WHERE key=? AND status='uncertain'", (key,))
            # Persist uncertainty BEFORE send. Any timeout/crash must reconcile.
            with self.transaction() as db:
                db.execute("UPDATE digest_batches SET status='uncertain' WHERE key=? AND status='pending'", (key,))
            receipt = transport.send(key, row['payload'], self.destination)
            return self.confirm(row, receipt)
        finally:
            os.close(fd)

    def confirm(self, row, receipt):
        encoded = self.receipt(row, receipt)
        with self.transaction() as db:
            current = db.execute('SELECT * FROM digest_batches WHERE key=? AND stream=?', (row['key'], self.stream)).fetchone()
            require(current is not None and current['payload'] == row['payload'], 'report changed')
            if current['status'] == 'confirmed':
                require(current['receipt'] == encoded, 'conflicting remote delivery')
            else:
                require(current['status'] == 'uncertain', 'report not dispatched')
                db.execute("UPDATE digest_batches SET status='confirmed',receipt=? WHERE key=?", (encoded, row['key']))
                db.execute('UPDATE digest_cursors SET cutoff=? WHERE stream=?', (row['cutoff'], self.stream))
        return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--db', required=True)
    parser.add_argument('--repository', required=True)
    parser.add_argument('--destination', required=True)
    parser.add_argument('--start', required=True)
    parser.add_argument('--branch', default='main')
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--until'); group.add_argument('--sydney-date')
    args = parser.parse_args()
    digest = Digest(args.db, args.repository, args.destination, args.start, args.branch)
    print(json.dumps(digest.prepare(coordinator.GitHub(args.repository), args.until or cutoff(args.sydney_date))))


if __name__ == '__main__':
    main()
