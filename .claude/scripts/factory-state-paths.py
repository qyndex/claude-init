#!/usr/bin/env python3
"""Exact inert state namespaces and bounded immutable-tree traversal; no origin grant."""
import json
import re


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def valid_hash(value, size):
    return isinstance(value, str) and re.fullmatch(r'[0-9a-f]{'+str(size)+'}', value) is not None


def validate_entry(item):
    require(isinstance(item, dict) and valid_hash(item.get('sha'), 40), 'state entry identity invalid')
    path = item.get('path')
    require(isinstance(path, str), 'state path invalid')
    checked_path = path.replace('receipt-archive/pending/', 'receipt-archive/index/', 1)
    if item.get('type') == 'tree':
        allowed = path in {'reports', 'receipt-archive', 'receipt-archive/objects', 'receipt-archive/materials', 'receipt-archive/index', 'receipt-archive/discovery', 'receipt-archive/progress', 'receipt-archive/pending', 'receipt-archive/outcomes', 'receipt-archive/origin', 'receipt-archive/backfill', 'receipt-archive/projection'} or re.fullmatch(r'receipt-archive/backfill/[0-9a-f]{64}(/[0-9a-f]{2})?', checked_path) or re.fullmatch(r'receipt-archive/outcomes/[0-9a-f]{64}(/[0-9a-f]{2})?', checked_path) or re.fullmatch(r'receipt-archive/(objects|materials)/[0-9a-f]{2}', checked_path) or re.fullmatch(r'receipt-archive/index/[0-9a-f]{64}(/identities(/[0-9a-f]{2})?)?', checked_path) or re.fullmatch(r'receipt-archive/index/[0-9a-f]{64}(/[0-9]{3}){1,3}', checked_path)
        require(item.get('mode') == '040000' and bool(allowed), 'state tree path/mode invalid')
    else:
        allowed = path == 'README.md' or re.fullmatch(r'reports/[0-9a-f]{64}\.json', checked_path) or re.fullmatch(r'receipt-archive/(discovery|progress|origin|backfill|projection)/[0-9a-f]{64}\.json', checked_path)
        sharded = re.fullmatch(r'receipt-archive/(objects|materials)/([0-9a-f]{2})/([0-9a-f]{64})\.json', checked_path)
        identity = re.fullmatch(r'receipt-archive/index/[0-9a-f]{64}/identities/([0-9a-f]{2})/([0-9a-f]{64})\.json', checked_path)
        segment = re.fullmatch(r'receipt-archive/index/[0-9a-f]{64}/([0-9]{3})/([0-9]{3})/([0-9]{3})/([0-9]{12})\.json', checked_path)
        outcome = re.fullmatch(r'receipt-archive/outcomes/[0-9a-f]{64}/([0-9a-f]{2})/([0-9a-f]{64})\.json', path)
        backfill = re.fullmatch(r'receipt-archive/backfill/[0-9a-f]{64}/([0-9a-f]{2})/([0-9a-f]{64})\.json', path)
        allowed = allowed or (backfill and backfill[2].startswith(backfill[1]))
        allowed = allowed or (outcome and outcome[2].startswith(outcome[1]))
        allowed = allowed or (segment and segment[4].startswith(segment[1]+segment[2]+segment[3]))
        allowed = allowed or (sharded and sharded[3].startswith(sharded[2])) or (identity and identity[2].startswith(identity[1]))
        if path.startswith('receipt-archive/'):
            require(type(item.get('size')) is int and 0 < item['size'] <= 1048576, 'archive entry size exceeds bound')
        require(item.get('type') == 'blob' and item.get('mode') == '100644' and bool(allowed), 'state blob path/mode invalid')
    return item


def validate_tree(entries):
    require(isinstance(entries, list), 'state tree entries malformed')
    paths = set()
    for entry in entries:
        validate_entry(entry)
        require(entry['path'] not in paths, 'state tree path duplicated')
        paths.add(entry['path'])
    return entries


def validate_segment(segment, repository, stream, number):
    require(isinstance(segment, dict) and set(segment) == {'schema_version', 'repository', 'stream', 'number', 'records'}, 'archive index schema differs')
    require(type(segment['schema_version']) is int and segment['schema_version'] == 1 and segment['repository'] == repository and valid_hash(stream, 64) and segment['stream'] == stream and type(number) is int and 0 <= number < 10**12 and type(segment['number']) is int and segment['number'] == number, 'archive index sequence/identity differs')
    rows = segment['records']
    require(isinstance(rows, list) and 0 < len(rows) <= 256 and len(json.dumps(segment).encode()) <= 1048576, 'archive index segment bound exceeded')
    identities = set(); hashes = set()
    for row in rows:
        require(isinstance(row, dict) and set(row) == {'run_id', 'attempt', 'artifact_id', 'record_sha256'} and all(type(row[k]) is int and row[k] > 0 for k in ('run_id', 'attempt', 'artifact_id')) and valid_hash(row['record_sha256'], 64), 'archive index record malformed')
        identity = (row['run_id'], row['attempt'], row['artifact_id'])
        require(identity not in identities and row['record_sha256'] not in hashes, 'archive index duplicate identity/content')
        identities.add(identity); hashes.add(row['record_sha256'])
    return segment


def scan_tree(api, root, tree_sha, *, cursor=None, page_budget=100):
    """Traverse immutable subtrees; partial results NEVER authorize origin/projection.

    Resume cursors require an independently authenticated protected checkpoint.
    Merely presenting this JSON or its root hash is not authenticated coverage.
    """
    require(root == f'repos/{api.repo}', 'foreign state traversal repository')
    require(valid_hash(tree_sha, 40) and type(page_budget) is int and 0 < page_budget <= 100, 'state traversal identity/budget invalid')
    if cursor is None:
        pending = [{'prefix': '', 'sha': tree_sha}]
    else:
        require(isinstance(cursor, dict) and set(cursor) == {'root', 'pending'} and cursor['root'] == tree_sha and isinstance(cursor['pending'], list) and 0 < len(cursor['pending']) <= 4096, 'state traversal cursor differs')
        pending = [dict(node) for node in cursor['pending']]
    require(len({(node.get('prefix'), node.get('sha')) for node in pending}) == len(pending), 'state traversal cursor duplicated')
    for node in pending:
        require(set(node) == {'prefix', 'sha'}, 'state traversal cursor schema differs')
        if node['prefix']:
            validate_entry({'path': node['prefix'], 'sha': node['sha'], 'type': 'tree', 'mode': '040000'})
        else:
            require(node['sha'] == tree_sha, 'state traversal root differs')
    entries = []; consumed = 0; pages = 0
    while pending and pages < page_budget and consumed <= 32505856:
        node = pending.pop(0)
        value = api.request(root + '/git/trees/' + node['sha'])
        require(isinstance(value, dict), 'state tree response malformed')
        size = len(json.dumps(value).encode()); consumed += size; pages += 1
        require(size <= 1048576 and consumed <= 33554432 and value.get('sha') == node['sha'] and value.get('truncated') is False and isinstance(value.get('tree'), list), 'state tree incomplete/capacity gap')
        children = []
        for item in value['tree']:
            require(isinstance(item, dict) and isinstance(item.get('path'), str) and '/' not in item['path'] and item['path'] not in ('.', '..'), 'state subtree entry not immediate')
            entry = dict(item, path=(node['prefix']+'/' if node['prefix'] else '')+item['path'])
            validate_entry(entry); entries.append(entry)
            if entry['type'] == 'tree':
                children.append({'prefix': entry['path'], 'sha': entry['sha']})
        validate_tree(entries)
        pending.extend(children)
        require(len(pending) <= 4096, 'state traversal frontier capacity gap')
    return {'entries': entries, 'complete': not pending, 'cursor': {'root': tree_sha, 'pending': pending} if pending else None, 'pages': pages}


def segment_path(stream, number):
    require(valid_hash(stream, 64) and type(number) is int and 0 <= number < 10**12, 'archive segment path identity invalid')
    digits = f'{number:012d}'
    return f'receipt-archive/index/{stream}/{digits[:3]}/{digits[3:6]}/{digits[6:9]}/{digits}.json'


def pending_segment_path(stream, number):
    return segment_path(stream, number).replace('receipt-archive/index/', 'receipt-archive/pending/', 1)
