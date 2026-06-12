#!/usr/bin/env bash
# E2E: P5.1 greenfield-6 (setup transactional validate) + P5.2 hooks-engineering-5 (dep-freshness latency)
set -u
R=/Volumes/M/sourcecode/qyndex/claude-init
HOOK="$R/verify/2026-06-12-e2e-fixes/staged/.claude/hooks/pre-bash-dep-freshness.sh"
pass=0; fail=0
chk() { local d=$1 e=$2 a=$3; if [ "$e" = "$a" ]; then echo "PASS: $d"; pass=$((pass+1)); else echo "FAIL: $d (want $e got $a)"; fail=$((fail+1)); fi; }

T=$(mktemp -d); cd "$T"; mkdir -p bin .claude/hooks/.log
cat > bin/curl <<'CURL'
#!/bin/bash
sleep "${CURL_DELAY:-0}"
for a in "$@"; do case "$a" in
  *registry.npmjs.org*|*pypi.org*) [ "${REG_RC:-0}" != 0 ] && exit 7; echo '{"version":"2.0.0","info":{"version":"2.0.0"}}'; exit 0 ;;
  *api.osv.dev*) [ "${OSV_RC:-0}" != 0 ] && exit 7; echo "${OSV_BODY:-{\"vulns\":[]}}"; exit 0 ;;
esac; done
exit 0
CURL
chmod +x bin/curl
export PATH="$T/bin:$PATH"
run_hook() { printf '{"tool_input":{"command":"%s"}}' "$1" | bash "$HOOK"; }
export CLAUDE_SESSION_ID=sess1

# clean install allowed + cached
out=$(run_hook "npm install left-pad@2.0.0"); rc=$?
chk "hook: clean install → allow (silent)" 0 "$([ $rc = 0 ] && [ -z "$out" ]; echo $?)"
chk "hook: allow verdict cached"           0 "$(ls .claude/hooks/.log/dep-freshness-cache/sess1-npm-left-pad-2.0.0 >/dev/null 2>&1; echo $?)"
# replay without network at all
rm -f bin/curl
out=$(run_hook "npm install left-pad@2.0.0"); rc=$?
chk "hook: cache replay needs NO network"  0 "$([ $rc = 0 ] && [ -z "$out" ]; echo $?)"

# deny cached + replayed verbatim
cat > bin/curl <<'CURL'
#!/bin/bash
for a in "$@"; do case "$a" in
  *registry.npmjs.org*) echo '{"version":"2.0.0"}'; exit 0 ;;
  *api.osv.dev*) echo '{"vulns":[{"id":"GHSA-xxxx"}]}'; exit 0 ;;
esac; done
CURL
chmod +x bin/curl
out=$(run_hook "npm install evil@1.0.0")
chk "hook: vuln install → deny"            0 "$(echo "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null; echo $?)"
rm -f bin/curl
out2=$(run_hook "npm install evil@1.0.0")
chk "hook: deny replayed from cache"       0 "$(echo "$out2" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null; echo $?)"

# fail-closed ask is NOT cached (network recovery re-probes)
cat > bin/curl <<'CURL'
#!/bin/bash
exit 7
CURL
chmod +x bin/curl
out=$(run_hook "npm install flaky@3.0.0")
chk "hook: unreachable registry → ask"     0 "$(echo "$out" | jq -e '.hookSpecificOutput.permissionDecision == "ask"' >/dev/null; echo $?)"
cat > bin/curl <<'CURL'
#!/bin/bash
for a in "$@"; do case "$a" in
  *registry.npmjs.org*) echo '{"version":"3.0.0"}'; exit 0 ;;
  *api.osv.dev*) echo '{"vulns":[]}'; exit 0 ;;
esac; done
CURL
chmod +x bin/curl
out=$(run_hook "npm install flaky@3.0.0")
chk "hook: ask not cached — recovers to allow" 0 "$([ -z "$out" ]; echo $?)"

# operator airgap flag: allow + loud log, no probe
rm -f bin/curl
out=$(DEP_FRESHNESS_OFFLINE=1 run_hook "npm install mirror-pkg@1.0.0"); rc=$?
chk "hook: DEP_FRESHNESS_OFFLINE=1 → allow"    0 "$([ $rc = 0 ] && [ -z "$out" ]; echo $?)"
chk "hook: declared-offline logged"            0 "$(grep -q 'declared-offline pkg=mirror-pkg' .claude/hooks/.log/dep-freshness-fallback.log; echo $?)"
# FORCE_OFFLINE (test hook) still asks
out=$(DEP_FRESHNESS_FORCE_OFFLINE=1 run_hook "npm install x-pkg@1.0.0")
chk "hook: FORCE_OFFLINE still fail-closed ask" 0 "$(echo "$out" | jq -e '.hookSpecificOutput.permissionDecision == "ask"' >/dev/null; echo $?)"

# concurrency: explicit version, both probes sleep 2s → wall < 3.5s
cat > bin/curl <<'CURL'
#!/bin/bash
sleep 2
for a in "$@"; do case "$a" in
  *registry.npmjs.org*) echo '{"version":"9.0.0"}'; exit 0 ;;
  *api.osv.dev*) echo '{"vulns":[]}'; exit 0 ;;
esac; done
CURL
chmod +x bin/curl
t0=$(date +%s)
run_hook "npm install timed-pkg@9.0.0" >/dev/null
t1=$(date +%s)
chk "hook: probes run concurrently (<4s for 2×2s)" 0 "$([ $((t1 - t0)) -lt 4 ]; echo $?)"
chk "hook: no timeout-wrapper dependency (curl --max-time)" 0 "$(grep -q 'max-time 5' "$HOOK" && ! grep -qE '^\s*timeout [0-9]+ curl' "$HOOK"; echo $?)"
cd /; rm -rf "$T"

# P5.1: setup.sh transactional validate (static + behavioral via grep)
cd "$R"
chk "setup: validate rc captured, not set -e abort" 0 "$(grep -q 'validate_rc=0' .claude/scripts/setup.sh && grep -q 'bash .claude/scripts/validate.sh || validate_rc=' .claude/scripts/setup.sh; echo $?)"
chk "setup: continues + exits non-zero at END"      0 "$(grep -q 'Final validation (re-run after remaining steps)' .claude/scripts/setup.sh && grep -q 'exit "\$validate_rc"' .claude/scripts/setup.sh; echo $?)"
n=$(grep -n 'Final validation' .claude/scripts/setup.sh | cut -d: -f1 | head -1)
p=$(grep -n 'Installing canonical plugins' .claude/scripts/setup.sh | cut -d: -f1 | head -1)
chk "setup: plugin install reached before final gate" 0 "$([ "$p" -lt "$n" ]; echo $?)"

echo "----"; echo "dep-cache matrix: $pass pass / $fail fail"
[ "$fail" -eq 0 ]
