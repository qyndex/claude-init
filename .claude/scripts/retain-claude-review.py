#!/usr/bin/env python3
"""Retain bounded exact-head model review output; never grants factory authority."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import sys

MODEL = 'claude-sonnet-5-5'
LIMIT = 16 * 1024 * 1024


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
    require(type(result.get('num_turns')) is int and 0 < result['num_turns'] <= 40, 'review turn bound invalid')
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--role', choices=('code', 'security'), required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    # A fresh destination prevents an old passing report surviving a failed attempt.
    args.output.mkdir(parents=True, exist_ok=False)
    status = {'schema_version': 1, 'status': 'blocked', 'role': args.role}
    exit_code = 1
    try:
        require(os.environ.get('REVIEW_ACTION_OUTCOME') == 'success', 'review action did not succeed')
        event = load(Path(os.environ['GITHUB_EVENT_PATH']))
        pr = event['pull_request']
        expected = {'repository': event['repository']['full_name'], 'pr': pr['number'], 'head': pr['head']['sha'], 'role': args.role}
        require(re.fullmatch(r'[0-9a-f]{40}', expected['head']) is not None and type(expected['pr']) is int and expected['pr'] > 0, 'event binding invalid')
        execution = Path(os.environ['REVIEW_EXECUTION_FILE']).resolve(strict=True)
        temp = Path(os.environ['RUNNER_TEMP']).resolve(strict=True)
        require(execution.is_relative_to(temp), 'execution file outside runner temp')
        messages = load(execution)
        review = validate(messages, expected)
        digest = hashlib.sha256(execution.read_bytes()).hexdigest()
        blocked = any(row['severity'] in ('critical', 'high') for row in review['findings'])
        for name in ('GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT'):
            require(re.fullmatch('[1-9][0-9]*', os.environ.get(name, '')) is not None, 'workflow attempt binding missing')
        status.update(expected, status='changes-required' if blocked else 'reviewed', model=MODEL,
                      run_id=os.environ['GITHUB_RUN_ID'], run_attempt=os.environ['GITHUB_RUN_ATTEMPT'],
                      execution_sha256=digest, review=review)
        exit_code = int(blocked)
    except (ValueError, KeyError, OSError, TypeError, RecursionError):
        # Never copy raw execution, exception strings, tokens or tool transcripts.
        status['reason'] = 'missing-invalid-or-unsuccessful-review-evidence'
    (args.output / 'review.json').write_text(json.dumps(status, sort_keys=True, indent=2) + '\n')
    print('Retained review: ' + status['status'])
    return exit_code


if __name__ == '__main__':
    sys.exit(main())
