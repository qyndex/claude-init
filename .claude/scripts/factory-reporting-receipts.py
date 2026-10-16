#!/usr/bin/env python3
"""Reconstruct protected retained proof before a fixed typed reporting transfer."""
from contextlib import closing
import importlib.util
import json
from pathlib import Path
import sqlite3
import tempfile


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


archive = load('report_archive', 'factory-receipt-archive.py')
discovery = load('report_discovery', 'factory-receipt-discovery.py')
require = archive.require
DEFINITIONS = {
    'delivery_receipts': ('task TEXT PRIMARY KEY, revision TEXT NOT NULL, receipt TEXT NOT NULL', ('task', 'revision', 'receipt')),
    'delivery_provenance': ('task TEXT PRIMARY KEY, provenance TEXT NOT NULL', ('task', 'provenance')),
    'delivery_trust': ('task TEXT PRIMARY KEY, status TEXT NOT NULL', ('task', 'status')),
    'delivery_times': ('task TEXT PRIMARY KEY, merged_at TEXT NOT NULL', ('task', 'merged_at')),
    'delivery_interval': ('task TEXT PRIMARY KEY', ('task',)),
}
class ProjectionPending(ValueError):
    pass


COVERAGE_SQL = 'CREATE TABLE reporting_receipt_coverage(repository TEXT PRIMARY KEY, coverage_from TEXT NOT NULL, verified_until TEXT NOT NULL)'


class ReadOnly:
    def __init__(self, api):
        self.api = api; self.repo = api.repo
        for name in ('read_blobs', 'read_pull_requests'):
            method = getattr(api, name, None)
            if callable(method):setattr(self, name, method)

    def request(self, path, method='GET', payload=None):
        require(method == 'GET' and payload is None and
                (path == 'repos/'+self.repo or path.startswith('repos/'+self.repo+'/')),
                'reporting receipt transport must be same-repository read-only')
        return self.api.request(path, method, payload)


class Source:
    def __init__(self, api):self.api = api; self.repo = api.repo

    def request(self, path):
        require(path.startswith('repos/'+self.repo+'/actions/'), 'reporting receipt source must be same-repository Actions read')
        return self.api.request(path)

    def get(self, path):
        require(path.startswith('repos/'+self.repo+'/actions/'), 'reporting receipt source must be same-repository Actions read')
        return self.api.get(path)


def project_reporting(source_api, state_api, policy, report_path, trust_path, store,
                      approval_path, stream, *, interval_end, history_head, campaign, page_size=100, interval_scoped=False):
    """No caller SQLite/projection result is accepted as authentication evidence.

    Both validators perform actual protected reads. The only destination writes
    are fixed typed receipt rows, in one transaction, after complete coverage.
    """
    require(type(interval_scoped) is bool, 'reporting interval scope mode invalid')
    require(source_api.repo == state_api.repo == policy['repository'], 'reporting receipt repository differs')
    report = Path(report_path)
    require(report.is_absolute() and report.resolve() == report and report.is_file() and not report.is_symlink(),
            'existing canonical report database required')
    state = ReadOnly(state_api); source = Source(source_api)
    before = archive.verify_bootstrap(state, approval_path)
    approval_raw = Path(approval_path).read_bytes(); trust_raw = Path(trust_path).read_bytes()
    with tempfile.TemporaryDirectory(prefix='factory-report-receipts-') as temporary:
        receipt_db = Path(temporary)/'receipts.sqlite'
        projection = archive.reconstruct_interval(state, policy, receipt_db, trust_path, store,
                    approval_path, stream, interval_end=interval_end, history_head=history_head, campaign=campaign, interval_scoped=interval_scoped)
        if projection.get('projection_complete') is not True:raise ProjectionPending('retained reporting projection incomplete')
        coverage = discovery.coverage(source, state, policy, trust_path, store, approval_path, stream,
                    interval_end=interval_end, projection_end=interval_end, history_head=history_head,
                    campaign=campaign, page_size=page_size, interval_scoped=interval_scoped)
        if not (all(coverage.get(key) is True for key in ('coverage_complete', 'source_partition_complete', 'frozen_projection_complete')) and
                coverage.get('verified_until') == interval_end and coverage.get('gaps') == [] and
                coverage.get('task_credit') is False and coverage.get('all_history_complete') is False):
            raise ProjectionPending('retained reporting coverage incomplete')
        require(coverage.get('repository') == policy['repository'] and
                coverage.get('coverage_from') == before['coverage_from'] and
                archive.instant(coverage['coverage_from']) <= archive.instant(coverage['verified_until']),
                'retained reporting coverage binding differs')
        rows = {}
        with closing(sqlite3.connect(receipt_db)) as db:
            objects = db.execute('SELECT type,name,sql FROM sqlite_master').fetchall()
            expected = {(name, 'CREATE TABLE '+name+'('+definition+')') for name,(definition,_) in DEFINITIONS.items()}
            require({(name,sql) for kind,name,sql in objects if kind == 'table'} == expected and
                    all(kind == 'table' or (kind == 'index' and sql is None and name in {'sqlite_autoindex_'+table+'_1' for table in DEFINITIONS}) for kind,name,sql in objects),
                    'retained reporting receipt schema differs')
            for name,(_,columns) in DEFINITIONS.items():
                rows[name] = db.execute('SELECT '+','.join(columns)+' FROM '+name+' ORDER BY task').fetchall()
                require(all(all(type(value) is str and value for value in row) for row in rows[name]), 'retained reporting row types differ')
        require(len(json.dumps(rows).encode()) <= 33554432, 'retained reporting transfer capacity gap')
        tasks = {row[0] for row in rows['delivery_receipts']}
        require(all({row[0] for row in rows[name]} == tasks for name in ('delivery_provenance','delivery_trust','delivery_times')) and
                {row[0] for row in rows['delivery_interval']} <= tasks, 'retained reporting task sets differ')
        require(archive.verify_bootstrap(state, approval_path) == before and Path(approval_path).read_bytes() == approval_raw and
                Path(trust_path).read_bytes() == trust_raw, 'retained reporting origin or trust changed')
        with closing(sqlite3.connect(report)) as db, db:
            db.execute('BEGIN IMMEDIATE')
            require(not db.execute("SELECT name FROM sqlite_master WHERE type='trigger'").fetchone(), 'reporting database triggers unsupported')
            existing = db.execute("SELECT type,sql FROM sqlite_master WHERE name='reporting_receipt_coverage'").fetchall()
            require(not existing or existing == [('table', COVERAGE_SQL)], 'reporting coverage destination schema differs')
            if not existing:db.execute(COVERAGE_SQL)
            require(all(row[0] == policy['repository'] for row in db.execute('SELECT repository FROM reporting_receipt_coverage')),
                    'reporting coverage repository differs')
            require(all(origin == coverage['coverage_from'] and archive.instant(until) <= archive.instant(coverage['verified_until'])
                        for origin,until in db.execute('SELECT coverage_from,verified_until FROM reporting_receipt_coverage')),
                    'reporting coverage regressed or origin differs')
            for name,(definition,columns) in DEFINITIONS.items():
                existing = db.execute('SELECT type,sql FROM sqlite_master WHERE name=?', (name,)).fetchall()
                require(not existing or existing == [('table','CREATE TABLE '+name+'('+definition+')')], 'reporting receipt destination schema differs')
                db.execute('CREATE TABLE IF NOT EXISTS '+name+'('+definition+')')
                old = dict((row[0],tuple(row)) for row in db.execute('SELECT '+','.join(columns)+' FROM '+name))
                new = {row[0]:tuple(row) for row in rows[name]}
                if name not in ('delivery_trust','delivery_interval'):
                    require(all(task in new and new[task] == row for task,row in old.items()), 'reporting retained fact conflicts or disappears')
                if old == new:
                    continue
                db.execute('DELETE FROM '+name)
                db.executemany('INSERT INTO '+name+' VALUES('+','.join('?' for _ in columns)+')', rows[name])
            marker = (coverage['repository'], coverage['coverage_from'], coverage['verified_until'])
            if db.execute('SELECT * FROM reporting_receipt_coverage').fetchall() != [marker]:
                db.execute('DELETE FROM reporting_receipt_coverage')
                db.execute('INSERT INTO reporting_receipt_coverage VALUES(?,?,?)', marker)
    return {'facts_count':len(tasks), 'coverage_complete':True, 'all_history_complete':False, 'task_credit':False}
