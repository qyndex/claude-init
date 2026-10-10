#!/usr/bin/env python3
"""Trusted operator feedback projection; task ledger and protected policy remain authority."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sqlite3
import sys

spec = importlib.util.spec_from_file_location('digest', Path(__file__).with_name('factory-digest.py'))
digest = importlib.util.module_from_spec(spec); spec.loader.exec_module(digest)
runtime_spec = importlib.util.spec_from_file_location('runtime', Path(__file__).with_name('factory-runtime.py'))
runtime = importlib.util.module_from_spec(runtime_spec); runtime_spec.loader.exec_module(runtime)
require = digest.require
canonical = digest.canonical


class Feedback:
    def __init__(self, database, repository):
        require(re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository or ''), 'repository required')
        self.store = runtime.Store(database); self.repository = repository
        with self.store.transaction() as db:
            db.execute('CREATE TABLE IF NOT EXISTS factory_feedback(id TEXT PRIMARY KEY, document TEXT NOT NULL, status TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 0)')
            db.execute('CREATE TABLE IF NOT EXISTS feedback_amendments(feedback TEXT NOT NULL,version INTEGER NOT NULL,document TEXT NOT NULL,PRIMARY KEY(feedback,version))')
            db.execute('CREATE TABLE IF NOT EXISTS feedback_events(feedback TEXT NOT NULL,sequence INTEGER NOT NULL,event TEXT NOT NULL,PRIMARY KEY(feedback,sequence))')

    @staticmethod
    def event(db, identity, event):
        sequence = db.execute('SELECT COUNT(*) FROM feedback_events WHERE feedback=?', (identity,)).fetchone()[0] + 1
        db.execute('INSERT INTO feedback_events VALUES(?,?,?)', (identity, sequence, canonical(event)))

    def row(self, db, identity):
        row = db.execute('SELECT * FROM factory_feedback WHERE id=?', (identity,)).fetchone()
        require(row is not None and json.loads(row['document'])['repository'] == self.repository, 'unknown feedback')
        return row

    def validate_intake(self, reporting_database, document):
        require(set(document) == {'repository', 'source_ref', 'reporter', 'text', 'kind', 'digest_key', 'pull_requests'}, 'malformed feedback')
        require(document['repository'] == self.repository, 'foreign feedback')
        require(document['kind'] in {'defect', 'enhancement', 'requirement', 'priority', 'acceptance'}, 'unknown feedback classification')
        require(all(isinstance(document[k], str) and 0 < len(document[k]) <= 20000 for k in ('source_ref', 'reporter', 'text', 'digest_key')), 'feedback source/text missing')
        prs = document['pull_requests']
        require(isinstance(prs, list) and bool(prs) and all(type(p) is int and p > 0 for p in prs) and len(set(prs)) == len(prs), 'feature PR identity required')
        with sqlite3.connect(Path(reporting_database).resolve().as_uri() + '?mode=ro', uri=True) as reporting:
            reporting.row_factory = sqlite3.Row
            batch = reporting.execute('SELECT * FROM digest_batches WHERE key=?', (document['digest_key'],)).fetchone()
            require(batch is not None and batch['status'] == 'confirmed', 'source digest not delivered')
            receipt = json.loads(batch['receipt']); payload = json.loads(batch['payload'])
            require(receipt['key'] == batch['key'] and receipt['payload_sha256'] == hashlib.sha256(batch['payload'].encode()).hexdigest() and receipt['destination'] == payload['destination'] and receipt['message_id'], 'source delivery receipt differs')
            require(payload['repository'] == self.repository and set(prs) <= {p['pr'] for p in payload['merges']}, 'feedback feature absent from source digest')
        identity = 'FB-' + hashlib.sha256(canonical([self.repository, document['source_ref']]).encode()).hexdigest()
        encoded = canonical(document)
        return identity, encoded

    def intake(self, reporting_database, document):
        return self.intake_batch(reporting_database, [document])[0]

    def intake_batch(self, reporting_database, documents):
        require(isinstance(documents, list) and len(documents) <= 1000, 'feedback batch too large')
        prepared = [(document, *self.validate_intake(reporting_database, document)) for document in documents]
        require(len({identity for _, identity, _ in prepared}) == len(prepared), 'duplicate feedback source in batch')
        with self.store.transaction() as db:
            for document, identity, encoded in prepared:
                old = db.execute('SELECT document FROM factory_feedback WHERE id=?', (identity,)).fetchone()
                require(old is None or old[0] == encoded, 'source replay conflicts with original feedback')
                if old is None:
                    db.execute('INSERT INTO factory_feedback(id,document,status) VALUES(?,?,?)', (identity, encoded, 'open'))
                    self.event(db, identity, {'type': 'captured', 'document': document})
        return [identity for _, identity, _ in prepared]

    def plan(self, identity, amendment, policy):
        require(set(amendment) == {'impact', 'bindings', 'supersedes'}, 'malformed amendment')
        require(isinstance(amendment['impact'], str) and 0 < len(amendment['impact']) <= 20000, 'impact analysis required')
        bindings = amendment['bindings']; old_revisions = amendment['supersedes']
        require(policy['repository'] == self.repository and isinstance(bindings, list) and bool(bindings) and isinstance(old_revisions, list), 'approved amendment mapping required')
        require(len({b['task'] for b in bindings}) == len(bindings), 'duplicate amendment task')
        for binding in bindings:
            require(set(binding) == {'task', 'spec', 'revision'}, 'invalid amendment binding')
            approved = policy['specs'][binding['spec']]
            require(binding['revision'] == approved['sha256'] and binding['task'] in approved.get('task_ids', []), 'amendment not approved by protected policy')
        require(all(isinstance(r, str) and re.fullmatch(r'[a-f0-9]{64}', r) for r in old_revisions) and len(set(old_revisions)) == len(old_revisions), 'invalid superseded revision')
        require(not set(old_revisions) & {b['revision'] for b in bindings}, 'new revision also superseded')
        encoded = canonical(amendment)
        require(policy.get('feedback_amendments', {}).get(identity) == hashlib.sha256(encoded.encode()).hexdigest(), 'full amendment impact/supersession not approved')
        with self.store.transaction() as db:
            row = self.row(db, identity)
            if row['version']:
                previous = db.execute('SELECT document FROM feedback_amendments WHERE feedback=? AND version=?', (identity, row['version'])).fetchone()[0]
                if previous == encoded:
                    return row['version']
            require(row['status'] != 'accepted', 'accepted feedback requires new source signal')
            for binding in bindings:
                task = self.store.row(db, binding['task'])
                require(task['revision'] == binding['revision'] and task['state'] != 'cancelled', 'task ledger projection differs')
            # Revisions are explicit operator-approved impact decisions; completed deliveries retain history.
            for revision in old_revisions:
                require(db.execute('SELECT 1 FROM tasks WHERE revision=?', (revision,)).fetchone(), 'unknown superseded work')
                db.execute("UPDATE outbox SET status='uncertain',expires=NULL WHERE status='dispatching' AND task IN (SELECT id FROM tasks WHERE revision=? AND state NOT IN ('merged','cancelled','blocked'))", (revision,))
                db.execute("UPDATE tasks SET state='blocked',owner=NULL,expires=NULL,fence=fence+1 WHERE revision=? AND state NOT IN ('merged','cancelled','blocked')", (revision,))
            version = row['version'] + 1
            db.execute('INSERT INTO feedback_amendments VALUES(?,?,?)', (identity, version, encoded))
            db.execute("UPDATE factory_feedback SET status='planned',version=? WHERE id=?", (version, identity))
            self.event(db, identity, {'type': 'planned', 'version': version, 'amendment': amendment})
            return version

    def reconcile(self, identity):
        with self.store.transaction() as db:
            row = self.row(db, identity)
            if row['status'] in {'open', 'accepted'}:
                return row['status']
            amendment = json.loads(db.execute('SELECT document FROM feedback_amendments WHERE feedback=? AND version=?', (identity, row['version'])).fetchone()[0])
            tables = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            complete = {'delivery_receipts', 'delivery_provenance'} <= tables
            for binding in amendment['bindings']:
                task = self.store.row(db, binding['task'])
                if not complete or task['state'] != 'merged' or task['revision'] != binding['revision']:
                    complete = False; continue
                receipt = db.execute('SELECT * FROM delivery_receipts WHERE task=?', (binding['task'],)).fetchone()
                proof = db.execute('SELECT provenance FROM delivery_provenance WHERE task=?', (binding['task'],)).fetchone()
                if receipt is None or proof is None:
                    complete = False; continue
                delivery = json.loads(receipt['receipt']); provenance = json.loads(proof[0]); attested = provenance['receipt']
                require(receipt['revision'] == binding['revision'] == attested['spec_sha256'] and attested['spec'] == binding['spec'], 'delivery revision differs')
                require(delivery['repository'] == self.repository == attested['repository'] and delivery['pr'] == attested['pull_request'] and delivery['merge_sha'] == attested['merge_sha'] and attested['task_ids'] == [binding['task']] and attested['merged'] is True and attested['eligible'] is True and type(provenance['run_id']) is int and provenance['run_id'] > 0, 'delivery provenance differs')
            status = 'delivered' if complete else 'planned'
            if row['status'] != status:
                db.execute('UPDATE factory_feedback SET status=? WHERE id=?', (status, identity))
                self.event(db, identity, {'type': status, 'version': row['version']})
            return status

    def accept(self, identity, operator, source_ref):
        require(all(isinstance(v, str) and bool(v.strip()) for v in (operator, source_ref)), 'explicit operator acceptance source required')
        require(self.reconcile(identity) in {'delivered', 'accepted'}, 'feedback not fully delivered')
        event = {'type': 'accepted', 'operator': operator, 'source_ref': source_ref}
        with self.store.transaction() as db:
            row = self.row(db, identity)
            previous = db.execute('SELECT event FROM feedback_events WHERE feedback=? ORDER BY sequence DESC LIMIT 1', (identity,)).fetchone()[0]
            if row['status'] == 'accepted':
                require(previous == canonical(event), 'acceptance replay conflicts'); return
            require(row['status'] == 'delivered', 'feedback changed before acceptance')
            db.execute("UPDATE factory_feedback SET status='accepted' WHERE id=?", (identity,))
            self.event(db, identity, event)

    def reconcile_spec(self, spec_id):
        with self.store.transaction() as db:
            identities = [r['id'] for r in db.execute('SELECT id,document FROM factory_feedback') if json.loads(r['document'])['repository'] == self.repository]
        result = {}
        for identity in identities:
            with self.store.transaction() as db:
                row = self.row(db, identity)
                amendment = db.execute('SELECT document FROM feedback_amendments WHERE feedback=? AND version=?', (identity, row['version'])).fetchone()
            if amendment and any(b['spec'] == spec_id for b in json.loads(amendment[0])['bindings']):
                result[identity] = self.reconcile(identity)
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--db', required=True); parser.add_argument('--repository', required=True)
    parser.add_argument('--reconcile-spec', required=True)
    args = parser.parse_args()
    require(Path(args.db).is_absolute() and Path(args.db).is_file(), 'existing protected runtime database required')
    print(json.dumps(Feedback(args.db, args.repository).reconcile_spec(args.reconcile_spec)))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError, sqlite3.Error):
        print('Feedback blocked; inspect trusted authority and receipts.', file=sys.stderr); sys.exit(1)
