#!/usr/bin/env bash
# E2E: P4.10 release-deploy-6, failure-recovery-4, ci-gates-4,6 — CI plumbing batch
set -u
R=/Volumes/M/sourcecode/qyndex/claude-init
SG="$R/verify/2026-06-12-e2e-fixes/staged"
pass=0; fail=0
chk() { local d=$1 e=$2 a=$3; if [ "$e" = "$a" ]; then echo "PASS: $d"; pass=$((pass+1)); else echo "FAIL: $d (want $e got $a)"; fail=$((fail+1)); fi; }

# 1. YAML validity
for wf in daily-failure-autofix claude-review claude-security pr-review; do
  chk "staged $wf.yml valid YAML" 0 "$(ruby -ryaml -e "YAML.load_file('$SG/.github/workflows/$wf.yml')" >/dev/null 2>&1; echo $?)"
done

# 2. autofix workflow semantics
AF="$SG/.github/workflows/daily-failure-autofix.yml"
chk "autofix: GH_TOKEN in spawn step"        0 "$(awk '/Spawn claude --bg/,/run: \|/' "$AF" | grep -q 'GH_TOKEN'; echo $?)"
chk "autofix: dead DATE_LABEL dropped"       1 "$(grep -q 'DATE_LABEL' "$AF"; echo $?)"
chk "autofix: no-PR label present"           0 "$(grep -q 'autofix-no-pr' "$AF"; echo $?)"

# execute the verify-PR step body with stub gh
T=$(mktemp -d); cd "$T"; mkdir bin
cat > bin/gh <<'GH'
#!/bin/bash
case "$1" in
  pr)    [ "${HAS_PR:-0}" = 1 ] && echo "https://github.com/o/r/pull/9" || echo "" ;;
  issue) echo "$*" >> "${GH_LOG:-/dev/null}" ;;
esac
GH
chmod +x bin/gh; export PATH="$T/bin:$PATH"
body=$(awk '/Verify a fix PR exists/,0' "$AF" | sed -n '/run: \|/,$p' | sed '1d' | sed 's/^          //')
rc_no=$(GH_LOG="$T/g1" RUN_URL_BODY=u bash -c "$body" >/dev/null 2>&1; echo $?)
rc_yes=$(HAS_PR=1 GH_LOG="$T/g2" RUN_URL_BODY=u bash -c "$body" >/dev/null 2>&1; echo $?)
chk "autofix: no PR → step exits 1"          1 "$rc_no"
chk "autofix: no PR → escalation issue"      0 "$(grep -q 'AUTOFIX PRODUCED NO PR' "$T/g1"; echo $?)"
chk "autofix: PR exists → step exits 0"      0 "$rc_yes"
cd /; rm -rf "$T"

# 3. API-key preflight (extract + execute)
for wf in claude-review claude-security; do
  body=$(awk '/Preflight — ANTHROPIC_API_KEY/,/Checkout/' "$SG/.github/workflows/$wf.yml" | sed -n '/run: \|/,/^      -/p' | sed '1d;$d' | sed 's/^          //')
  chk "$wf: preflight no key → exit 1 + ::error" 0 "$(HAS_KEY=false bash -c "$body" 2>&1 | grep -q '::error::ANTHROPIC_API_KEY'; echo $?)"
  chk "$wf: preflight key set → exit 0"          0 "$(HAS_KEY=true bash -c "$body" >/dev/null 2>&1; echo $?)"
done

# 4. concurrency / filters / draft guards
chk "claude-review: concurrency group"       0 "$(grep -q 'group: claude-review-' "$SG/.github/workflows/claude-review.yml"; echo $?)"
chk "claude-security: concurrency group"     0 "$(grep -q 'group: claude-security-' "$SG/.github/workflows/claude-security.yml"; echo $?)"
chk "claude-security: branches [main]"       0 "$(grep -q 'branches: \[main\]' "$SG/.github/workflows/claude-security.yml"; echo $?)"
chk "pr-review: concurrency group"           0 "$(grep -q 'group: pr-review-' "$SG/.github/workflows/pr-review.yml"; echo $?)"
chk "pr-review: draft guard"                 0 "$(grep -q 'draft == false' "$SG/.github/workflows/pr-review.yml"; echo $?)"

# 5. setup.sh release-please block (extract + run in stub repos)
setup_block=$(sed -n '/step "Release-please config/,/step "ANTHROPIC_API_KEY/p' "$R/.claude/scripts/setup.sh" | sed '$d')
runner() { # run block in cwd with stub helpers
  bash -c "step(){ :; }; ok(){ echo OK:\$*; }; warn(){ echo WARN:\$*; }; note(){ :; }; $setup_block"
}
T=$(mktemp -d); cd "$T"
cp "$R/release-please-config.json" .
printf '{"name":"@acme/shop"}\n' > package.json
out=$(runner)
chk "setup: node stack → release-type set"   0 "$(jq -e '."release-type"=="node" and .packages."."."package-name"=="@acme/shop"' release-please-config.json >/dev/null; echo $?)"
chk "setup: manifest seeded"                 0 "$([ -f .release-please-manifest.json ]; echo $?)"
out2=$(runner)
chk "setup: idempotent (already customized)" 0 "$(echo "$out2" | grep -q 'already customized'; echo $?)"
cd /; rm -rf "$T"
T=$(mktemp -d); cd "$T"
cp "$R/release-please-config.json" .
printf '[tool.poetry]\nname="api"\n' > pyproject.toml
runner >/dev/null
chk "setup: python stack detected"           0 "$(jq -e '."release-type"=="python"' release-please-config.json >/dev/null; echo $?)"
cd /; rm -rf "$T"
T=$(mktemp -d); cd "$T"
cp "$R/release-please-config.json" .
out=$(runner)
chk "setup: no stack → loud placeholder warn" 0 "$(echo "$out" | grep -q 'PLACEHOLDER package-name and no stack'; echo $?)"
cd /; rm -rf "$T"

# 6. doctor + factory state + ship/release rewrites
cd "$R"
out=$(bash .claude/scripts/harness-doctor.sh 2>/dev/null)
chk "doctor: release-please check present"   0 "$(echo "$out" | grep -q 'release-please config'; echo $?)"
chk "doctor: API-key check present"          0 "$(echo "$out" | grep -q 'ANTHROPIC_API_KEY secret'; echo $?)"
chk "factory: manifest seeded at 2.0.0"      0 "$(jq -e '."." == "2.0.0"' .release-please-manifest.json >/dev/null; echo $?)"
chk "ship: step 10 = merge release-please PR"   0 "$(grep -q 'merging the release-please PR' "$SG/.claude/skills/ship/SKILL.md"; echo $?)"
chk "release agent: no hand-tagging"            1 "$(grep -q 'git tag v<version>' "$SG/.claude/agents/specialists/release.md"; echo $?)"
chk "setup.sh: API-key preflight step"          0 "$(grep -q 'ANTHROPIC_API_KEY preflight' .claude/scripts/setup.sh; echo $?)"

echo "----"; echo "ci-plumbing matrix: $pass pass / $fail fail"
[ "$fail" -eq 0 ]
