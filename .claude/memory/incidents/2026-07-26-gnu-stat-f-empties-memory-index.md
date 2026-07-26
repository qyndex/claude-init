---
name: 2026-07-26-gnu-stat-f-empties-memory-index
description: "CI-only empty memory index — GNU `stat -f %m` pollutes $mtime → jq tonumber throws → build_entry emits nothing. Fixed by probing `-c %Y` first."
status: resolved
created: 2026-07-26
metadata:
  type: incident
  status: resolved
---

# CI-only empty memory index (GNU `stat -f` pollution)

## Symptom

`harness-validate` failed on `adr-supersession.sh` (1/8) and `archives-and-modified.sh` (5/6)
**only in GitHub Actions** (ubuntu-latest); both passed on local macOS. Assertions read index
fields as empty (`got ''`). Failing on main for 5+ commits before it was noticed (masked earlier
by the Actions billing block that failed every job in ~2s).

## Error signature

```
jq: error (at <unknown>): string ("  File: \"...) cannot be parsed as a number
✓ Indexed 0 memory artifacts → .claude/memory/index.jsonl   (0 bytes)
```

## Root cause

`.claude/scripts/memory-index.sh:114`

```bash
local mtime=$(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null)
```

GNU `stat -f` is `--file-system` (BSD's `-f` is the format flag). On Linux, `stat -f %m file`
prints multi-line filesystem info to stdout **and** exits 1 → the `||` fallback also runs and
appends the real epoch → `$mtime` is a multi-line poisoned string → `jq -nc '… mtime: ($mtime |
tonumber)'` throws → `build_entry` prints nothing → `_rebuild_index` skips every file → empty
`index.jsonl` → all downstream `jq select(...)` reads return empty.

On macOS the BSD-first probe succeeds immediately, so the poison branch never runs — hence
green locally, red in CI.

## Ruled out (wrong theories tried first)

- CRLF/whitespace on the `---` frontmatter fence (patched `extract_field` anyway — valid hardening)
- `with_lock` undefined because a fixture doesn't copy `lib/` (patched with a no-op fallback —
  valid hardening; but CI checks out the full repo, so lib/ is present there)
- awk variant (mawk), locale (`LANG=`), grep/sed differences

## Fix

Swap the probe order at two sites so the GNU form runs first:

- `memory-index.sh:114` → `stat -c %Y … || stat -f %m …`
- `lib/with-lock.sh:32` → same reorder (latent twin — breaks stale-lock age math on Linux under
  contention; not exercised by these tests but wrong on GNU regardless)

## Verification

Docker `ubuntu:latest` repro (mirrors CI): `adr-supersession` 8/8, `archives-and-modified` 6/6
after the reorder. macOS still returns a clean numeric epoch.

## Prevention

Pattern: [[bsd-vs-gnu-stat-flag-collision]] — never rely on `stat -f %m || stat -c %Y` ordering;
GNU `-f` half-succeeds (stdout pollution + exit 1). Probe `-c %Y` first.
