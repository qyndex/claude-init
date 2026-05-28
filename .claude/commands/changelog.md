---
description: Generate a CHANGELOG.md entry from Conventional Commits since the last release tag. Use after /ship if release-please isn't configured.
argument-hint: "[version, e.g. v1.2.0]"
allowed-tools: Bash, Read, Edit, Write
disable-model-invocation: true
---

# /changelog — Generate CHANGELOG entry

Convert Conventional Commits into a release section.

## Process

1. Find the last tag: `git describe --tags --abbrev=0`.
2. List commits since then: `git log <tag>..HEAD --format='%s'`.
3. Group by type (feat, fix, perf, docs, refactor, chore, revert).
4. Format as Keep-A-Changelog section.
5. Prepend to `CHANGELOG.md` (or create it).

```!
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
echo "Last tag: ${LAST_TAG:-<none — using full history>}"
echo
echo "=== Commits since ${LAST_TAG:-beginning} ==="
if [ -n "$LAST_TAG" ]; then
  git log "${LAST_TAG}..HEAD" --format='%s' --no-merges
else
  git log --format='%s' --no-merges | head -100
fi
```

## Output format

```markdown
## [<version>] — <YYYY-MM-DD>

### Added
- <feat: summary>

### Fixed
- <fix: summary>

### Changed
- <refactor: summary>

### Performance
- <perf: summary>

### Documentation
- <docs: summary>
```

Skip empty sections. Include the PR number if extractable from the commit message.

After writing, ask the user whether to commit the CHANGELOG bump and tag the release.
