#!/usr/bin/env bash
# reconcile-shipped.sh — after PRs merge to main, bring the ledger into agreement
# with reality: flip spec status → shipped, initiative STATE → shipped, and record
# each shipped PR (with its proof pointers) into a machine-readable ship-log the
# daily briefing consumes.
#
# This is the on-merge half of autonomous shipping. autonomous-ship.sh arms the
# merge; GitHub merges when checks pass; THIS reconciles the local artifacts so
# tasks/TASKS.md, specs/, and initiatives/ stop drifting from what actually shipped.
#
# It composes the existing, tested primitives rather than reimplementing them:
#   - spec-status-sync.sh   (spec frontmatter approved → shipped, TASKS-driven)
#   - initiative-state.sh   (STATE.md phase → shipped)
#   - shipped-registry.sh   (specs/SHIPPED.md, evidence-driven)
# and adds the one missing piece: a PR-merge → ship-log record with proof links.
#
# Output: .claude/state/ship-log.jsonl  (one line per reconciled merged PR)
#   {pr, title, mergedAt, mergeCommit, url, specs:[...], tasks:[...],
#    initiatives:[...], evidence:[paths], decisions:[from commit trailers]}
#
# Usage:
#   reconcile-shipped.sh                 # reconcile PRs merged since the last run
#   reconcile-shipped.sh --since <iso>   # reconcile PRs merged since <iso>
#   reconcile-shipped.sh --dry-run       # report, write nothing
# Test hooks: RECON_REPO, RECON_STATE_DIR, RECON_TASKS, RECON_MERGED_JSON (feed a
# fixture PR list instead of calling gh).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

STATE_DIR="${RECON_STATE_DIR:-.claude/state}"
SHIP_LOG="$STATE_DIR/ship-log.jsonl"
WATERMARK="$STATE_DIR/.reconcile-watermark"
TASKS="${RECON_TASKS:-tasks/TASKS.md}"
DRY=0; SINCE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --since) SINCE="${2:-}"; shift ;;
    *) echo "reconcile-shipped: unknown arg '$1'"; exit 2 ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || { echo "reconcile-shipped: jq required"; exit 5; }
mkdir -p "$STATE_DIR"

# Turn newline-separated stdin into a JSON string array, ALWAYS valid ([] when
# empty). `jq -R . | jq -s .` alone handles the empty case (yields []); the earlier
# `grep -v '^$' | ... || echo []` form double-printed ("[]\n[]") because under
# pipefail the grep's exit-1 on all-blank input fired the `||` AFTER jq had already
# emitted []. `jq -Rs 'split by lines, drop blanks'` does the whole thing in one
# invocation with no pipefail trap and no double-emit.
to_json_array() { jq -R -s 'split("\n") | map(select(length > 0))'; }

# Resolve the "since" boundary: explicit flag > watermark > 24h ago (first run).
if [ -z "$SINCE" ]; then
  if [ -f "$WATERMARK" ]; then SINCE=$(cat "$WATERMARK"); fi
fi

# Fetch merged PRs (test hook: RECON_MERGED_JSON is a file of the gh JSON array).
if [ -n "${RECON_MERGED_JSON:-}" ]; then
  merged=$(cat "$RECON_MERGED_JSON")
else
  command -v gh >/dev/null 2>&1 || { echo "reconcile-shipped: gh required (or set RECON_MERGED_JSON)"; exit 5; }
  REPO="${RECON_REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)}"
  [ -n "$REPO" ] || { echo "reconcile-shipped: cannot resolve repo"; exit 5; }
  merged=$(gh pr list --repo "$REPO" --state merged --limit 50 \
    --json number,title,mergedAt,mergeCommit,url,headRefName 2>/dev/null || echo '[]')
fi

# Filter to PRs merged after SINCE (if set).
if [ -n "$SINCE" ]; then
  merged=$(printf '%s' "$merged" | jq --arg s "$SINCE" '[.[] | select(.mergedAt > $s)]')
fi

count=$(printf '%s' "$merged" | jq 'length')
if [ "${count:-0}" -eq 0 ]; then
  echo "reconcile-shipped: no newly-merged PRs since ${SINCE:-<first run>}"
  exit 0
fi
echo "reconcile-shipped: $count merged PR(s) to reconcile since ${SINCE:-<first run>}"

# For each merged PR, derive the specs/tasks it shipped and gather proof.
newest_merged="$SINCE"
records=""
while IFS= read -r pr; do
  num=$(printf '%s' "$pr" | jq -r '.number')
  title=$(printf '%s' "$pr" | jq -r '.title')
  mergedAt=$(printf '%s' "$pr" | jq -r '.mergedAt')
  sha=$(printf '%s' "$pr" | jq -r '.mergeCommit.oid // ""')
  url=$(printf '%s' "$pr" | jq -r '.url')

  # track newest mergedAt for the watermark
  if [ -z "$newest_merged" ] || [ "$mergedAt" \> "$newest_merged" ]; then newest_merged="$mergedAt"; fi

  # Decisions: pull the git-trailer decision fields from the merge commit body.
  decisions="[]"
  if [ -n "$sha" ]; then
    # grep exits 1 on no match → the pipeline yields empty; `|| true` keeps it
    # running and the `[ -n ]` guard below falls back to [] so --argjson is valid.
    d=$(git log -1 --format='%b' "$sha" 2>/dev/null \
      | grep -iE '^(Constraint|Rejected|Directive|Confidence|Scope-risk):' \
      | jq -R . | jq -s . 2>/dev/null || true)
    [ -n "$d" ] && decisions="$d"
  fi

  # Which specs are now fully shipped per TASKS.md? (all spec:NNN lines [x]/[s])
  # Reuse the same predicate as spec-status-sync.sh but just to LABEL the record.
  specs=$(awk '
    match($0, /spec:[0-9A-Za-z-]+/) {
      s=substr($0,RSTART+5,RLENGTH-5)
      total[s]++
      if ($0 ~ /^- \[[xs]\]/) done[s]++
    }
    END { for (s in total) if (done[s]==total[s]) print s }
  ' "$TASKS" 2>/dev/null | to_json_array)

  # Tasks flipped shipped ([s]) that reference those specs — with ledger proof path.
  tasks=$(grep -oE '^- \[s\]  T-[0-9A-Za-z-]+' "$TASKS" 2>/dev/null \
    | grep -oE 'T-[0-9A-Za-z-]+' | to_json_array)

  # Evidence bundles for the shipped specs (proof the AC passed).
  evidence="[]"
  if [ "$(printf '%s' "$specs" | jq 'length')" -gt 0 ]; then
    ev_paths=""
    while IFS= read -r sp; do
      [ -z "$sp" ] && continue
      # newest evidence.json carrying this spec id
      p=$(grep -rlE "\"spec\"[: ]*\"?$sp\"?" verify --include=evidence.json 2>/dev/null | sort | tail -1)
      [ -n "$p" ] && ev_paths="$ev_paths$p"$'\n'
    done < <(printf '%s' "$specs" | jq -r '.[]')
    evidence=$(printf '%s' "$ev_paths" | to_json_array)
  fi

  # Initiatives now shipped (STATE.md phase: shipped) — proof path is the STATE file.
  inits=$(grep -rlE '^phase:[[:space:]]*shipped' initiatives/active 2>/dev/null | to_json_array)

  # Belt-and-braces: any list var that came back empty (a pipeline that exited
  # non-zero under pipefail before the `|| echo []` could fire) defaults to [] so
  # --argjson never receives an empty string (which errors "invalid JSON text").
  rec=$(jq -c -n \
    --argjson pr "${num:-0}" --arg title "$title" --arg mergedAt "$mergedAt" \
    --arg sha "$sha" --arg url "$url" \
    --argjson specs "${specs:-[]}" --argjson tasks "${tasks:-[]}" \
    --argjson initiatives "${inits:-[]}" --argjson evidence "${evidence:-[]}" \
    --argjson decisions "${decisions:-[]}" \
    '{pr:$pr, title:$title, mergedAt:$mergedAt, mergeCommit:$sha, url:$url,
      specs:$specs, tasks:$tasks, initiatives:$initiatives,
      evidence:$evidence, decisions:$decisions}')
  records="$records$rec"$'\n'
  echo "  #$num $title — specs:$(printf '%s' "$specs" | jq -c .) tasks:$(printf '%s' "$tasks" | jq 'length') evidence:$(printf '%s' "$evidence" | jq 'length')"
done < <(printf '%s' "$merged" | jq -c '.[]')

if [ "$DRY" -eq 1 ]; then
  echo "reconcile-shipped: DRY-RUN — would append $count record(s) to $SHIP_LOG and run status syncs"
  printf '%s' "$records" | grep -v '^$'
  exit 0
fi

# Run the real status-flip primitives (advisory, idempotent).
[ -x .claude/scripts/spec-status-sync.sh ] && bash .claude/scripts/spec-status-sync.sh >/dev/null 2>&1 || true
[ -x .claude/scripts/initiative-state.sh ] && bash .claude/scripts/initiative-state.sh sync >/dev/null 2>&1 || true
[ -x .claude/scripts/shipped-registry.sh ] && bash .claude/scripts/shipped-registry.sh >/dev/null 2>&1 || true

# spec-005 G3: harvest each merged commit's decision trailers into a DRAFT ADR
# (status: proposed). Draft-only + deduped by hash, so this is safe to run every
# reconcile; a human accepts via /adr-walk. Best-effort — a harvest hiccup must not
# fail the reconcile.
if [ -x .claude/scripts/harvest-decisions.sh ]; then
  while IFS= read -r rec; do
    [ -z "$rec" ] && continue
    hsha=$(printf '%s' "$rec" | jq -r '.mergeCommit // ""')
    [ -n "$hsha" ] && bash .claude/scripts/harvest-decisions.sh "$hsha" >/dev/null 2>&1 || true
  done < <(printf '%s' "$records")
fi

# Append records (dedupe by pr number: skip any pr already in the log).
touch "$SHIP_LOG"
while IFS= read -r rec; do
  [ -z "$rec" ] && continue
  n=$(printf '%s' "$rec" | jq -r '.pr')
  if grep -q "\"pr\":$n," "$SHIP_LOG" 2>/dev/null || grep -q "\"pr\":$n}" "$SHIP_LOG" 2>/dev/null; then
    continue
  fi
  printf '%s\n' "$rec" >> "$SHIP_LOG"
done < <(printf '%s' "$records")

# Advance the watermark so the next run only sees newer merges.
[ -n "$newest_merged" ] && printf '%s' "$newest_merged" > "$WATERMARK"
echo "reconcile-shipped: appended to $SHIP_LOG; watermark → ${newest_merged}"
