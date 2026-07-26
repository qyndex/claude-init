---
name: bsd-vs-gnu-stat-flag-collision
description: "Portable mtime: probe GNU `stat -c %Y` BEFORE BSD `stat -f %m` — GNU -f half-succeeds (stdout pollution + exit 1) and poisons the value on Linux."
status: active
created: 2026-07-26
metadata:
  type: pattern
  status: active
---

# BSD-vs-GNU `stat` flag collision

## Rule

To read a file's mtime portably, **probe GNU first, BSD as fallback**:

```bash
mtime=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null)
```

Never the reverse (`-f %m || -c %Y`).

## Why the reverse is a trap

`-f` means different things on the two platforms:

- **BSD/macOS**: `-f <fmt>` is the _format_ flag → `stat -f %m file` prints the mtime epoch. Clean.
- **GNU/Linux**: `-f` is `--file-system` → `stat -f %m file` **prints multi-line filesystem
  info to stdout** (`  File: "..."`, `ID:`, `Block size:` …) _and then_ exits 1.

The exit-1 is the trap: it looks like a clean rejection (so `|| fallback` fires), but stdout was
already polluted. With BSD-first ordering on Linux you get `filesystem-dump\n<real-epoch>` — a
multi-line string. Downstream `jq | tonumber`, arithmetic `$(( … - mt ))`, or `[ "$x" -gt … ]`
then break.

## How it bit us

`memory-index.sh` built mtime with BSD-first ordering. On macOS the first probe succeeded and the
poison branch never ran, so it passed locally. In CI (Ubuntu) the poisoned `$mtime` reached
`jq -nc '… mtime: ($mtime | tonumber)'`, `tonumber` threw, `build_entry` emitted nothing, the
rebuild indexed 0 files, and every memory-index test failed with empty reads (`got ''`) — **only
in CI**. Incident: [[2026-07-26-gnu-stat-f-empties-memory-index]].

## Generalization

Any tool with a flag that means different things on GNU vs BSD and **half-succeeds** (writes
output _and_ returns non-zero) defeats `A || B` fallback ordering. Order the probe so the
non-polluting form runs first. Other known offenders: `sed -i` (GNU vs BSD suffix arg),
`date -d` vs `date -v`, `readlink -f`.
