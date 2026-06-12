#!/usr/bin/env bash
# E2E: P5.6 docs-truth-1 — check-doc-consistency wired + ARCH-table diff; audit-doc-claims widened
set -u
R=/Volumes/M/sourcecode/qyndex/claude-init
pass=0; fail=0
chk() { local d=$1 e=$2 a=$3; if [ "$e" = "$a" ]; then echo "PASS: $d"; pass=$((pass+1)); else echo "FAIL: $d (want $e got $a)"; fail=$((fail+1)); fi; }

cd "$R"

# ── wiring ──
chk "validate.sh has [model-doc-consistency] category" 0 "$(grep -q '\[model-doc-consistency\]' .claude/scripts/validate.sh; echo $?)"
chk "validate.sh invokes check-doc-consistency.sh"     0 "$(grep -q 'check-doc-consistency.sh' .claude/scripts/validate.sh; echo $?)"
out=$(bash .claude/scripts/validate.sh 2>&1)
chk "validate runs the category (output present)"      0 "$(echo "$out" | grep -q 'model-doc-consistency'; echo $?)"
# pre-install: live constitution §V lacks anti-slop-reviewer → by-design RED
chk "pre-install RED: §V missing anti-slop-reviewer"   0 "$(echo "$out" | grep -q 'doc/model drift.*anti-slop-reviewer'; echo $?)"
# staged constitution fixes it
chk "staged constitution: anti-slop-reviewer in §V"    0 "$(grep -q 'feedback-extractor, anti-slop-reviewer' verify/2026-06-12-e2e-fixes/staged/.claude/CLAUDE.md; echo $?)"

# ── ARCH-table diff logic (behavioral, sandboxed) ──
# cdc resolves ROOT from its own script path, so install the copy INSIDE the sandbox
T=$(mktemp -d); cd "$T"
mkdir -p .claude/agents/core .claude/scripts docs
cp "$R/.claude/scripts/check-doc-consistency.sh" .claude/scripts/
printf -- '---\nname: alpha\nmodel: opus\n---\n' > .claude/agents/core/alpha.md
# matching root/constitution routing so phase 1 passes
printf -- '- **Opus 4.8** → alpha (x)\n' > CLAUDE.md
printf -- '- **Opus 4.8** → alpha (x)\n' > .claude/CLAUDE.md
printf '| **alpha** | core | opus | Read | stuff |\n' > docs/ARCHITECTURE.md
o=$(bash .claude/scripts/check-doc-consistency.sh 2>&1); rc=$?
chk "cdc: clean sandbox passes"                         0 "$rc"
# model drift detected
printf '| **alpha** | core | sonnet | Read | stuff |\n' > docs/ARCHITECTURE.md
o=$(bash .claude/scripts/check-doc-consistency.sh 2>&1); rc=$?
chk "cdc: model drift in ARCH table → exit 1"           1 "$rc"
chk "cdc: drift names the agent"                        0 "$(echo "$o" | grep -q "model drift: alpha"; echo $?)"
# missing agent detected
: > docs/ARCHITECTURE.md
o=$(bash .claude/scripts/check-doc-consistency.sh 2>&1); rc=$?
chk "cdc: agent missing from ARCH table → exit 1"       1 "$rc"
cd "$R"; rm -rf "$T"

# ── widened audit-doc-claims ──
chk "audit: repo scan green after orphan fixes"        0 "$(bash .claude/scripts/audit-doc-claims.sh >/dev/null 2>&1; echo $?)"
chk "audit: AUTOPILOT:157 lists real contexts"         0 "$(grep -q '\`evidence-gate\`, \`harness-validate\`' docs/AUTOPILOT.md || grep -q 'evidence-gate.*harness-validate' docs/AUTOPILOT.md; echo $?)"
chk "audit: docs/research excluded from scan set"      0 "$(grep -q "not -path 'docs/research/\*'" .claude/scripts/audit-doc-claims.sh; echo $?)"
# active-voice: synthetic orphan fires
T=$(mktemp -d)
mkdir -p "$T/docs"
echo 'The gate `no-such-gate-xyz.sh` enforces this rule.' > "$T/docs/x.md"
o=$(AUDIT_DOC_ROOT="$T/docs" bash .claude/scripts/audit-doc-claims.sh 2>&1); rc=$?
chk "audit: active-voice orphan → exit 1"              1 "$rc"
chk "audit: active-voice orphan named"                 0 "$(echo "$o" | grep -q 'active-voice.*no-such-gate-xyz.sh'; echo $?)"
# active-voice: real gate passes
echo 'The gate `validate.sh` enforces this rule.' > "$T/docs/x.md"
chk "audit: active-voice real gate passes"             0 "$(AUDIT_DOC_ROOT="$T/docs" bash .claude/scripts/audit-doc-claims.sh >/dev/null 2>&1; echo $?)"
# required-check: orphan context fires
echo 'Note that `bogus-check` is a required check here.' > "$T/docs/x.md"
o=$(AUDIT_DOC_ROOT="$T/docs" bash .claude/scripts/audit-doc-claims.sh 2>&1); rc=$?
chk "audit: bogus required-check → exit 1"             1 "$rc"
chk "audit: bogus required-check named"                0 "$(echo "$o" | grep -q 'not in main-protection.json contexts: bogus-check'; echo $?)"
# required-check: real context passes
echo 'Note that `evidence-gate` is a required check here.' > "$T/docs/x.md"
chk "audit: real required-check passes"                0 "$(AUDIT_DOC_ROOT="$T/docs" bash .claude/scripts/audit-doc-claims.sh >/dev/null 2>&1; echo $?)"
rm -rf "$T"

# original passive-voice path untouched
T=$(mktemp -d); mkdir -p "$T/docs"
echo 'This is enforced by `definitely-not-real.sh` always.' > "$T/docs/y.md"
chk "audit: passive-voice path still fires"            1 "$(AUDIT_DOC_ROOT="$T/docs" bash .claude/scripts/audit-doc-claims.sh >/dev/null 2>&1; echo $?)"
rm -rf "$T"

chk "both scripts executable"                          0 "$([ -x .claude/scripts/audit-doc-claims.sh ] && [ -x .claude/scripts/check-doc-consistency.sh ]; echo $?)"
chk "audit-doc-claims: bash -n clean"                  0 "$(bash -n .claude/scripts/audit-doc-claims.sh; echo $?)"
chk "check-doc-consistency: bash -n clean"             0 "$(bash -n .claude/scripts/check-doc-consistency.sh; echo $?)"

echo "----"; echo "doc-claims matrix: $pass pass / $fail fail"
[ "$fail" -eq 0 ]
