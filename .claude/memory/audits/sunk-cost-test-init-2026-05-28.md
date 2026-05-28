# Sunk-cost report — initiative test-init — 2026-05-28T02:17:43+10:00

## Resource accounting

| Dimension | Value |
|---|---|
| Wall-clock days active | ? |
| Tokens $ spent | $0 |
| Sessions tagged | 0 |
| Commits | 0 |
| Engineer authors | unknown |

## Specs under this initiative

| Status | Count |
|---|---|
| shipped | 0 |
| dropped/abandoned | 0 |
| paused | 0 |
| active | 0 |

## Value vs cost ratio

- Value: 0 specs shipped
- Sunk: $0 + 0 engineer-commits over ? days

## Linked artifacts

- Initiative: 
- Pivot manifests: `grep -l "test-init" pivots/active/ pivots/archive/ 2>/dev/null`
- Post-mortem (if abandoned): `.claude/memory/post-mortems/test-init-*.md`
- Decisions log entries: `grep "test-init" .swarms/coordinator/decisions.log`

## Caveats

- Token attribution requires Round 7 E `current-initiative` state file to be populated DURING the work. Historical sessions without the tag fall back to wall-clock + commit proxies.
- Engineer-commits is a proxy for person-time, not a measure of effort or outcome.
