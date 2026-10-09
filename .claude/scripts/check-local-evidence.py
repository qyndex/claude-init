#!/usr/bin/env python3
"""Check all local bootstrap bundles. This is not independent merge authority."""
import argparse
import importlib.util
import re
from pathlib import Path
import subprocess

module = importlib.util.spec_from_file_location('contract', Path(__file__).with_name('validate-candidate-evidence.py'))
contract = importlib.util.module_from_spec(module)
module.loader.exec_module(contract)


def validate(root, expected, paths):
    found = set()
    for path in paths:
        resolved = (root / path).resolve()
        contract.require(resolved.is_relative_to((root / 'verify').resolve()), 'evidence must remain under verify/')
        evidence = contract.load(resolved)
        sid = evidence.get('spec')
        contract.require(isinstance(sid, str) and re.fullmatch(r'\d+', sid) is not None and sid not in found, 'missing/duplicate spec identity')
        specs = list((root / 'specs/active').glob(f'{sid}-*.md'))
        contract.require(len(specs) == 1, 'spec identity is ambiguous or unavailable')
        text = specs[0].read_text().split('## Acceptance criteria', 1)
        contract.require(len(text) == 2, 'acceptance section missing')
        block = re.split(r'\n## ', text[1], maxsplit=1)[0]
        acs = set(re.findall(r'AC-\d+', block))
        contract.require(bool(acs), 'approved AC identifiers missing')
        contract.require(type(evidence.get('ac_total')) is int and type(evidence.get('ac_proven')) is int and evidence['ac_total'] == len(acs) and evidence['ac_proven'] == len(acs), 'incomplete AC counts')
        contract.require(evidence.get('ac_unproven') == [] and evidence.get('verdict') == 'PASS', 'AC proof incomplete')
        contract.require(type(evidence.get('smoke_exit_max')) is int and evidence['smoke_exit_max'] == 0, 'smoke not passing')
        contract.require(type(evidence.get('runner_exit')) is int and evidence['runner_exit'] == 0, 'runner not passing')
        commit = evidence.get('commit')
        contract.require(contract.digest(commit, 40), 'commit binding missing')
        contract.require(subprocess.run(['git', '-C', str(root), 'merge-base', '--is-ancestor', commit, 'HEAD'], capture_output=True).returncode == 0, 'foreign source commit')
        results = resolved.with_name('results.json')
        # Validate the entire JSON before spec-match consumes any tagged result.
        contract.load(results)
        contract.require(subprocess.run(['bash', str(root / '.claude/scripts/spec-match.sh'), sid, str(results)], cwd=root).returncode == 0, 'passing tagged AC results missing')
        found.add(sid)
    contract.require(set(expected).issubset(found), 'one or more touched specifications lack evidence')
    contract.require(bool(found), 'no local evidence bundles')
    print('Local evidence complete for: ' + ', '.join(sorted(found)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path.cwd())
    parser.add_argument('--changed-files', type=Path, required=True)
    parser.add_argument('--output-paths', type=Path, required=True)
    args = parser.parse_args()
    changed = args.changed_files.read_text().splitlines()
    expected = [match.group(1) for path in changed if (match := re.match(r'^specs/active/(\d+)-.*\.md$', path))]
    paths = [path for path in changed if re.fullmatch(r'verify/.+/evidence\.json', path)]
    validate(args.root.resolve(), expected, paths)
    args.output_paths.write_text('\n'.join(paths) + '\n')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError) as error:
        raise SystemExit(f'local evidence blocked: {error}')
