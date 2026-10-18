#!/usr/bin/env python3
"""Read AC IDs from the single Markdown acceptance section; fail closed."""
import re
import sys
from pathlib import Path

MAX_BYTES = 1048576

def criteria(raw):
    if not isinstance(raw, bytes) or not 0 < len(raw) <= MAX_BYTES:
        raise ValueError('specification size invalid')
    try:
        lines = re.split(r'\r\n|\r|\n', raw.decode('utf-8-sig'))
    except UnicodeError:
        raise ValueError('specification encoding invalid') from None
    sections = 0
    active = False
    found = set()
    fence = None
    for line in lines:
        marker = re.match(r'^ {0,3}(`{3,}|~{3,})(.*)$', line)
        if fence is not None:
            if marker and marker[1][0] == fence[0] and len(marker[1]) >= fence[1] and not marker[2].strip():
                fence = None
            continue
        if marker and marker[1][0] == '`' and '`' in marker[2]:
            raise ValueError('invalid backtick fence opener')
        if marker:
            fence = (marker[1][0], len(marker[1]))
            continue
        heading = re.match(r'^ {0,3}(#{1,2})[ \t]+(.*?)[ \t]*$', line)
        if heading:
            title = re.sub(r'[ \t]+#+[ \t]*$', '', heading[2]).strip()
            acceptance = len(heading[1]) == 2 and title.casefold() == 'acceptance criteria'
            if acceptance:
                sections += 1
            active = acceptance
            continue
        if not active and re.match(r'^ {0,3}(?:(?:[-+*]|[0-9]+[.)])[ \t]+)?(?:\*\*|__)?AC-[0-9]+\b', line):
            raise ValueError('acceptance definition outside acceptance section')
        if active:
            for value in re.findall(r'\bAC-([0-9]+)\b', line):
                if len(value) > 6 or int(value) == 0:
                    raise ValueError('acceptance identifier invalid')
                found.add('AC-' + str(int(value)))
    if fence is not None:
        raise ValueError('unterminated code fence')
    if sections != 1 or not found:
        raise ValueError('one nonempty acceptance section required')
    return sorted(found)

def main():
    if len(sys.argv) != 2:
        raise ValueError('one specification path required')
    with Path(sys.argv[1]).open('rb') as source:
        raw = source.read(MAX_BYTES + 1)
    print('\n'.join(criteria(raw)))

if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError):
        print('Acceptance criteria blocked: invalid or unavailable specification section.', file=sys.stderr)
        sys.exit(1)
