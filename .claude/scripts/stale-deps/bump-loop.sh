#!/usr/bin/env bash
# Stale-deps bump loop — Round 8 B.
#
# For each candidate in /tmp/candidates-<stack>.json:
#   1. Create worktree on branch claude/dep-<pkg>-<to>
#   2. Run stack-specific bump
#   3. Run local-pr-check.sh --quick → green: push + open PR (labeled by kind)
#   4. Red: spawn claude --bg ($3, 30 turns) with WebFetch'd migration guide
#   5. Re-test; if green push; if red, escalate (open issue, no PR)
#
# Per-candidate budget: $3 + 30 turns
# Hard daily cap on candidates: configurable via MAX_CANDIDATES env (default 5)

set -uo pipefail

STACK="${1:?stack required}"
MAX_CANDIDATES="${MAX_CANDIDATES:-5}"
CANDIDATES_FILE="/tmp/candidates-${STACK}.json"
[ -f "$CANDIDATES_FILE" ] || { echo "scan didn't produce $CANDIDATES_FILE"; exit 1; }

candidates=$(jq -c '.[]' "$CANDIDATES_FILE" | head -n "$MAX_CANDIDATES")
[ -z "$candidates" ] && { echo "no candidates to process"; exit 0; }

results_dir="/tmp/bump-results-${STACK}"
mkdir -p "$results_dir"
shipped=0
mediated=0
escalated=0

while IFS= read -r entry; do
  pkg=$(echo "$entry" | jq -r .pkg)
  from=$(echo "$entry" | jq -r .from)
  to=$(echo "$entry" | jq -r .to)
  kind=$(echo "$entry" | jq -r .kind)
  has_vuln=$(echo "$entry" | jq -r .has_vuln)
  osv_ids=$(echo "$entry" | jq -r '.osv_ids // [] | join(",")')

  safe_pkg=$(echo "$pkg" | sed 's|/|-|g;s|@|_|g')
  branch="claude/dep-${safe_pkg}-${to}"
  wt=".claude/worktrees/dep-${safe_pkg}-${to}"

  echo
  echo "→ Bumping $pkg: $from → $to ($kind) has_vuln=$has_vuln"

  # Create worktree
  git fetch origin main >/dev/null 2>&1 || true
  git worktree add -b "$branch" "$wt" origin/main 2>/dev/null || git worktree add "$wt" "$branch" 2>/dev/null

  pushd "$wt" >/dev/null || { escalated=$((escalated + 1)); continue; }

  # Run the bump per stack
  bump_ok=0
  case "$STACK" in
    npm|typescript)
      if [ -f pnpm-lock.yaml ]; then
        pnpm add "${pkg}@${to}" >/dev/null 2>&1 && bump_ok=1
      else
        npm install "${pkg}@${to}" --save >/dev/null 2>&1 && bump_ok=1
      fi
      ;;
    python|pypi)
      if [ -f pyproject.toml ] && command -v uv >/dev/null; then
        uv add "${pkg}==${to}" >/dev/null 2>&1 && bump_ok=1
      else
        pip install -U "${pkg}==${to}" >/dev/null 2>&1 && bump_ok=1
      fi
      ;;
    rust|crates)
      cargo update -p "$pkg" --precise "$to" >/dev/null 2>&1 && bump_ok=1
      ;;
    go)
      go get "${pkg}@${to}" >/dev/null 2>&1 && go mod tidy >/dev/null 2>&1 && bump_ok=1
      ;;
  esac

  if [ "$bump_ok" != "1" ]; then
    echo "  ✗ bump failed; escalating"
    popd >/dev/null
    git worktree remove --force "$wt" 2>/dev/null
    gh issue create --title "auto-bump escalated: $pkg $from → $to" \
      --body "Bump command failed in worktree. Stack=$STACK kind=$kind vulns=$osv_ids" \
      --label "auto-bump,auto-bump:escalated" >/dev/null 2>&1 || true
    escalated=$((escalated + 1))
    continue
  fi

  # Run local-pr-check --quick
  if bash ../../.claude/scripts/local-pr-check.sh --quick >/dev/null 2>&1; then
    echo "  ✓ quick check passed; pushing"
    git add -A
    label="auto-bump:${kind}"
    [ "$has_vuln" = "true" ] && label="auto-bump:vuln-fix"
    git commit -m "chore(deps): bump $pkg from $from to $to

$([ "$has_vuln" = "true" ] && echo "Fixes OSV: $osv_ids")
Type: $kind
Verified: local-pr-check --quick passed

Constraint:    auto-bump pipeline
Confidence:    high
Scope-risk:    localized" >/dev/null 2>&1

    git push -u origin "$branch" >/dev/null 2>&1
    gh pr create --title "chore(deps): bump $pkg $from → $to" \
      --body "Auto-bump from daily-stale-deps.yml. Kind: $kind. $([ "$has_vuln" = "true" ] && echo "Fixes vulns: $osv_ids")" \
      --label "auto-bump,$label" >/dev/null 2>&1 || true
    shipped=$((shipped + 1))
    popd >/dev/null
    continue
  fi

  # Red path: spawn claude --bg for code-fix
  echo "  ⚠ check failed; spawning claude mediation"
  if command -v claude >/dev/null; then
    mediation_prompt="Bump of $pkg from $from to $to ($kind) failed local-pr-check.
Read the failure in .claude/hooks/.log/local-pr/, fetch the package's CHANGELOG / migration guide via WebFetch, and apply minimal code fixes to make tests pass.
Constraint: ONLY edit files affected by the bump; do NOT add new features.
If unfixable within 30 turns, exit non-zero."

    claude -p --max-turns 30 --max-budget-usd 3 \
      --permission-mode auto \
      --append-system-prompt "$mediation_prompt" \
      "Fix the $pkg $from→$to bump" >/dev/null 2>&1

    # Re-run check
    if bash ../../.claude/scripts/local-pr-check.sh --quick >/dev/null 2>&1; then
      echo "  ✓ mediation succeeded; pushing"
      git add -A
      git commit -m "chore(deps): bump $pkg from $from to $to + code-fix

Type: $kind
Mediation: claude --bg fixed breaking changes
$([ "$has_vuln" = "true" ] && echo "Fixes OSV: $osv_ids")

Constraint:    auto-bump with mediation
Confidence:    medium
Scope-risk:    localized
Not-tested:    edge cases beyond the bump-affected paths" >/dev/null 2>&1

      git push -u origin "$branch" >/dev/null 2>&1
      gh pr create --title "chore(deps)!: bump $pkg $from → $to with code-fix" \
        --body "Auto-bump from daily-stale-deps.yml. Required claude mediation to resolve breaking changes." \
        --label "auto-bump,auto-bump:$kind,auto-bump:mediated" >/dev/null 2>&1 || true
      mediated=$((mediated + 1))
      popd >/dev/null
      continue
    fi
  fi

  # Escalate
  echo "  ✗ unresolved; escalating"
  popd >/dev/null
  git worktree remove --force "$wt" 2>/dev/null
  gh issue create --title "auto-bump escalated: $pkg $from → $to (mediation failed)" \
    --body "Stack=$STACK kind=$kind vulns=$osv_ids — claude mediation could not resolve. Human review needed." \
    --label "auto-bump,auto-bump:escalated" >/dev/null 2>&1 || true
  escalated=$((escalated + 1))
done <<< "$candidates"

echo
echo "bump-loop for $STACK: shipped=$shipped mediated=$mediated escalated=$escalated"
jq -nc --argjson shipped "$shipped" --argjson mediated "$mediated" --argjson escalated "$escalated" \
  '{stack: "'"$STACK"'", shipped: $shipped, mediated: $mediated, escalated: $escalated}' \
  > "$results_dir/summary.json"
