#!/usr/bin/env python3
"""Validate bounded exact-head tool-free review output; no merge authority."""
import json
from pathlib import Path
import re

MODEL = 'claude-sonnet-5-5'
LIMIT = 4_000_000
CLI_VERSION = '2.1.295'
SCHEMA = {'type': 'object', 'additionalProperties': False, 'required': ['repository', 'pr', 'head', 'role', 'summary', 'findings', 'suppressed'], 'properties': {'repository': {'type': 'string'}, 'pr': {'type': 'integer'}, 'head': {'type': 'string'}, 'role': {'enum': ['code', 'security']}, 'summary': {'type': 'string'}, 'suppressed': {'type': 'integer'}, 'findings': {'type': 'array', 'items': {'type': 'object', 'additionalProperties': False, 'required': ['severity', 'path', 'line', 'description'], 'properties': {'severity': {'enum': ['critical', 'high', 'medium', 'low', 'info']}, 'path': {'type': 'string'}, 'line': {'type': 'integer'}, 'description': {'type': 'string'}}}}}}


def require(ok, message):
    if not ok:
        raise ValueError(message)


def unique(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'duplicate JSON field')
        result[key] = value
    return result


def load(path):
    with path.open('rb') as stream:
        raw = stream.read(LIMIT + 1)
    require(0 < len(raw) <= LIMIT, 'review input size invalid')
    return json.loads(raw, object_pairs_hook=unique)


def validate(messages, expected):
    require(isinstance(messages, list) and bool(messages), 'execution messages missing')
    require(all(isinstance(row, dict) for row in messages), 'execution message invalid')
    results = [row for row in messages if row.get('type') == 'result']
    require(len(results) == 1 and messages[-1] is results[0], 'one terminal result required')
    result = results[0]
    require(result.get('subtype') == 'success' and result.get('is_error') is False, 'model execution unsuccessful')
    require(result.get('permission_denials') == [], 'denied or unknown tool access')
    usage = result.get('modelUsage')
    require(isinstance(usage, dict) and set(usage) == {MODEL}, 'observed reviewer model mismatch')
    require(isinstance(usage[MODEL], dict), 'observed usage malformed')
    for field in ('inputTokens', 'outputTokens', 'cacheReadInputTokens', 'cacheCreationInputTokens'):
        count = usage[MODEL].get(field)
        require((count is None and field.startswith('cache')) or (type(count) is int and 0 <= count <= 1000000000), 'observed token count invalid')
    require(type(result.get('num_turns')) is int and 0 < result['num_turns'] <= 3, 'review turn bound invalid')
    review = result.get('structured_output')
    require(isinstance(review, dict) and set(review) == {'repository', 'pr', 'head', 'role', 'summary', 'findings', 'suppressed'}, 'structured review missing or malformed')
    for name in ('repository', 'pr', 'head', 'role'):
        require(type(review[name]) is type(expected[name]) and review[name] == expected[name], 'review binding mismatch')
    require(isinstance(review['summary'], str) and 0 < len(review['summary'].strip()) <= 12000, 'review summary missing or oversized')
    require(type(review['suppressed']) is int and 0 <= review['suppressed'] <= 1000, 'suppression count invalid')
    findings = review['findings']
    require(isinstance(findings, list) and len(findings) <= 100, 'finding list invalid')
    for finding in findings:
        require(isinstance(finding, dict) and set(finding) == {'severity', 'path', 'line', 'description'}, 'finding shape invalid')
        require(finding['severity'] in ('critical', 'high', 'medium', 'low', 'info'), 'severity invalid')
        path = finding['path']
        require(isinstance(path, str) and 0 < len(path) <= 512 and not path.startswith('/') and all(part not in ('', '.', '..') for part in path.split('/')) and not re.search(r'[\x00-\x1f\x7f\\]', path), 'finding path invalid')
        require(type(finding['line']) is int and 0 < finding['line'] <= 1000000, 'finding line invalid')
        require(isinstance(finding['description'], str) and 0 < len(finding['description'].strip()) <= 8000, 'finding description invalid')
    return review
