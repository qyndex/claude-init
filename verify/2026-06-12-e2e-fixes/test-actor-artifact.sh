#!/usr/bin/env bash
# E2E: P5.4 ci-gates-5 + e2e-rig-5 — actor allowlist invariant; evidence artifact polish
set -u
R=/Volumes/M/sourcecode/qyndex/claude-init
SG="$R/verify/2026-06-12-e2e-fixes/staged"
pass=0; fail=0
chk() { local d=$1 e=$2 a=$3; if [ "$e" = "$a" ]; then echo "PASS: $d"; pass=$((pass+1)); else echo "FAIL: $d (want $e got $a)"; fail=$((fail+1)); fi; }

# staged claude.yml: allowlist on every trigger arm + still valid YAML
CY="$SG/.github/workflows/claude.yml"
chk "claude.yml (staged) valid YAML"          0 "$(ruby -ryaml -e "YAML.load_file('$CY')" >/dev/null 2>&1; echo $?)"
chk "claude.yml: 4 trigger arms guarded"      4 "$(grep -c 'github\.event\..*author_association' "$CY")"
chk "claude.yml: id-token kept (action needs it)" 0 "$(grep -q 'id-token: write' "$CY"; echo $?)"

# validate.sh invariant — mode-aware: pre-install the live claude.yml is unguarded
# (fail line present); post-install (INSTALLED=1) the guard is live (fail absent).
out=$(bash "$R/.claude/scripts/validate.sh" 2>&1)
if [ "${INSTALLED:-0}" = "1" ]; then
  chk "validate: installed claude.yml is guarded"  1 "$(echo "$out" | grep -q 'NO author_association guard'; echo $?)"
else
  chk "validate: flags unguarded live claude.yml" 0 "$(echo "$out" | grep -q 'NO author_association guard'; echo $?)"
fi
# synthetic: guarded workflow passes the check
T=$(mktemp -d); cd "$T"; mkdir -p .github/workflows
printf 'on:\n  issue_comment:\n    types: [created]\npermissions:\n  contents: write\njobs:\n  j:\n    if: contains(fromJSON(chr), github.event.comment.author_association)\n' > .github/workflows/guarded.yml
g=0
grep -qE '^[[:space:]]*(issue_comment|pull_request_review_comment):' .github/workflows/guarded.yml && \
  grep -qE '^[[:space:]]*contents:[[:space:]]*write' .github/workflows/guarded.yml && \
  grep -q 'author_association' .github/workflows/guarded.yml || g=1
chk "invariant logic: guarded workflow passes"  0 "$g"
cd /; rm -rf "$T"

# collect-evidence: per-worker artifact globbing (behavioral)
T=$(mktemp -d); cd "$T"
mkdir -p verify/2026-06-12-x/test-results/journey-chromium
: > verify/2026-06-12-x/test-results/journey-chromium/video.webm
: > verify/2026-06-12-x/test-results/journey-chromium/trace.zip
v=$(find verify/2026-06-12-x -maxdepth 3 -name 'video.webm' | head -1)
chk "evidence: nested video found by new glob"  0 "$([ -n "$v" ]; echo $?)"
chk "collect-evidence.sh uses find glob"        0 "$(grep -q "find \"\$date_dir\" -maxdepth 3 -name 'video.webm'" "$R/.claude/scripts/collect-evidence.sh"; echo $?)"
chk "collect-evidence.sh: Verdict token intact" 0 "$(grep -q 'Verdict' "$R/.claude/scripts/collect-evidence.sh"; echo $?)"
chk "collect-evidence.sh: UNPROVEN token intact" 0 "$(grep -q 'UNPROVEN' "$R/.claude/scripts/collect-evidence.sh"; echo $?)"
cd /; rm -rf "$T"

# staged evidence-gate: always-upload step
EG="$SG/.github/workflows/evidence-gate.yml"
chk "evidence-gate (staged) valid YAML"        0 "$(ruby -ryaml -e "YAML.load_file('$EG')" >/dev/null 2>&1; echo $?)"
chk "evidence-gate: if always() upload"        0 "$(grep -B2 'upload-artifact' "$EG" | grep -q 'always()'; echo $?)"
chk "evidence-gate: uploads verify/**"         0 "$(grep -q 'verify/\*\*' "$EG"; echo $?)"

# playwright template HAR note
chk "playwright template: HAR clobber caveat"  0 "$(grep -q 'CLOBBERED per worker' "$R/.claude/templates/evidence/playwright.config.ts"; echo $?)"

echo "----"; echo "actor-artifact matrix: $pass pass / $fail fail"
[ "$fail" -eq 0 ]
