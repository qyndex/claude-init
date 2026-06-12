#!/usr/bin/env bash
# E2E: P5.5 docs-truth-2..5 — doc bans in validate.sh, routine matrix + installer, doc fixes, README/ARCH regen
set -u
R=/Volumes/M/sourcecode/qyndex/claude-init
pass=0; fail=0
chk() { local d=$1 e=$2 a=$3; if [ "$e" = "$a" ]; then echo "PASS: $d"; pass=$((pass+1)); else echo "FAIL: $d (want $e got $a)"; fail=$((fail+1)); fi; }

cd "$R"
out=$(bash .claude/scripts/validate.sh 2>&1)

# ── doc fixes landed ──
chk "ONBOARDING: boolean-false advice gone"      1 "$(grep -q 'disableBypassPermissionsMode: false' docs/ONBOARDING.md; echo $?)"
chk "ONBOARDING: explains silently-ignored bool" 0 "$(grep -q 'silently ignored' docs/ONBOARDING.md; echo $?)"
chk "AUTOPILOT: string form documented"          0 "$(grep -q '"disableBypassPermissionsMode": "disable"' docs/AUTOPILOT.md; echo $?)"
chk "OPERATOR-MANUAL: [s] = skipped"             0 "$(grep -q '\[s\]. skipped' docs/OPERATOR-MANUAL.md; echo $?)"
chk "OPERATOR-MANUAL: [s] shipped gone"          1 "$(grep -qE '\[s\][^a-zA-Z]*shipped' docs/OPERATOR-MANUAL.md; echo $?)"
chk "OPERATOR-MANUAL: requires reason: noted"    0 "$(grep -q 'reason:.*line' docs/OPERATOR-MANUAL.md; echo $?)"

# ── validate.sh bans pass clean on fixed docs, fire on synthetic bad docs ──
chk "validate: bypass-bool ban green on repo"    0 "$(echo "$out" | grep -q 'docs never recommend boolean disableBypassPermissionsMode'; echo $?)"
chk "validate: legend ban green on repo"         0 "$(echo "$out" | grep -q 'docs agree with tasks/TASKS.md legend'; echo $?)"
# synthetic bad docs (behavioral: same grep logic as validate.sh)
T=$(mktemp -d); cd "$T"; mkdir docs
echo 'set disableBypassPermissionsMode: false in settings' > docs/bad1.md
echo '`[s]` shipped.' > docs/bad2.md
b1=$(grep -rnE 'disableBypassPermissionsMode[^a-zA-Z]*(true|false)' docs/ README.md 2>/dev/null | grep -v '^docs/research/' | grep -v 'silently ignore' || true)
b2=$(grep -rnE '\[s\][^a-zA-Z]*shipped' docs/ README.md 2>/dev/null | grep -v '^docs/research/' || true)
chk "ban logic: fires on synthetic bool doc"     0 "$([ -n "$b1" ]; echo $?)"
chk "ban logic: fires on synthetic [s]-shipped"  0 "$([ -n "$b2" ]; echo $?)"
# research exclusion honored
mkdir -p docs/research; mv docs/bad1.md docs/bad2.md docs/research/
b1=$(grep -rnE 'disableBypassPermissionsMode[^a-zA-Z]*(true|false)' docs/ README.md 2>/dev/null | grep -v '^docs/research/' | grep -v 'silently ignore' || true)
chk "ban logic: docs/research/ quotes exempt"    0 "$([ -z "$b1" ]; echo $?)"
cd "$R"; rm -rf "$T"

# ── routine matrix + installer coverage ──
chk "AUTOPILOT: routine matrix section"          0 "$(grep -q '### Routine installation matrix' docs/AUTOPILOT.md; echo $?)"
n_missing=0
for f in .claude/routines/*.yml; do
  rn=$(awk -F': *' '/^name:/{print $2; exit}' "$f")
  grep -q "\`$rn\`" docs/AUTOPILOT.md || { echo "  missing from matrix: $rn"; n_missing=$((n_missing+1)); }
done
chk "AUTOPILOT: matrix lists all 11 routines"    0 "$n_missing"
chk "OPERATOR-MANUAL: pointer to matrix"         0 "$(grep -q 'Routine installation' docs/OPERATOR-MANUAL.md; echo $?)"
# installer registers (or opt-in gates) every routine except the cloud one
inst_missing=0
for rn in appetite-circuit-breaker atlas-refresh constitution-compact-cron dream-cron feedback-poll feedback-triage gc-nightly hotfix-sentry-poll oq-aging quarterly-archive; do
  grep -q "$rn" .claude/scripts/install-overnight-tasks.sh || { echo "  installer missing: $rn"; inst_missing=$((inst_missing+1)); }
done
chk "installer: covers all 10 desktop routines"  0 "$inst_missing"
chk "installer: feedback-poll is opt-in"         0 "$(grep -q 'INSTALL_FEEDBACK_POLL' .claude/scripts/install-overnight-tasks.sh; echo $?)"
chk "installer: sentry-poll is opt-in"           0 "$(grep -q 'INSTALL_SENTRY_POLL' .claude/scripts/install-overnight-tasks.sh; echo $?)"
chk "installer: record() writes routine record"  0 "$(grep -q 'routines-installed' .claude/scripts/install-overnight-tasks.sh; echo $?)"
chk "doctor: routine installs check exists"      0 "$(grep -q 'routine installs' .claude/scripts/harness-doctor.sh; echo $?)"
chk "gitignore: routines-installed ignored"      0 "$(grep -q 'routines-installed' .gitignore; echo $?)"
chk "installer: bash -n clean"                   0 "$(bash -n .claude/scripts/install-overnight-tasks.sh; echo $?)"

# ── README / ARCHITECTURE regen ──
# ARCHITECTURE agent table model column matches every agent's frontmatter
arch_drift=0
for f in .claude/agents/*/*.md; do
  an=$(awk -F': *' '/^name:/{print $2; exit}' "$f"); am=$(awk -F': *' '/^model:/{print $2; exit}' "$f")
  row=$(grep -E "^\| \*\*$an\*\* \|" docs/ARCHITECTURE.md || true)
  [ -z "$row" ] && { echo "  agent missing from ARCH table: $an"; arch_drift=$((arch_drift+1)); continue; }
  echo "$row" | grep -q "| $am |" || { echo "  model drift in ARCH table: $an ($am)"; arch_drift=$((arch_drift+1)); }
done
chk "ARCHITECTURE: agent table = live frontmatter (18 agents)" 0 "$arch_drift"
chk "README: core agents line current"           0 "$(grep -q 'coordinator, feature-stream, roadmap-architect' README.md; echo $?)"
chk "README: honest truncation (58 skills)"      0 "$(grep -q '58 skills total' README.md; echo $?)"
chk "README: honest truncation (36 workflows)"   0 "$(grep -q '36 workflows total' README.md; echo $?)"
chk "README: honest truncation (25 hooks)"       0 "$(grep -q '25 hooks total' README.md; echo $?)"
chk "validate.sh: bash -n clean"                 0 "$(bash -n .claude/scripts/validate.sh; echo $?)"

echo "----"; echo "doc-truth matrix: $pass pass / $fail fail"
[ "$fail" -eq 0 ]
