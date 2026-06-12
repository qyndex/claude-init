#!/usr/bin/env bash
# E2E: P4.8 release-deploy-1,5 — DEPLOY_WIRED gate, deployment_status producer+consumer, doctor stub flag
set -u
R=/Volumes/M/sourcecode/qyndex/claude-init
SG="$R/verify/2026-06-12-e2e-fixes/staged"
pass=0; fail=0
chk() { local d=$1 e=$2 a=$3; if [ "$e" = "$a" ]; then echo "PASS: $d"; pass=$((pass+1)); else echo "FAIL: $d (want $e got $a)"; fail=$((fail+1)); fi; }

# 1. staged workflows are valid YAML
for wf in canary-deploy issue-lifecycle; do
  chk "staged $wf.yml is valid YAML" 0 "$(ruby -ryaml -e "YAML.load_file('$SG/.github/workflows/$wf.yml')" >/dev/null 2>&1; echo $?)"
done

# 2. canary gate semantics (static)
CD="$SG/.github/workflows/canary-deploy.yml"
chk "canary: first step refuses unwired"         0 "$(grep -q 'DEPLOY_WIRED is not' "$CD"; echo $?)"
chk "canary: unwired path exits 1"               0 "$(grep -A9 'Refuse to run unwired' "$CD" | grep -q 'exit 1'; echo $?)"
chk "canary: PROM_URL unset is now ::error"      0 "$(grep -q '::error::DEPLOY_WIRED=true but PROM_URL is not set' "$CD"; echo $?)"
chk "canary: no warn+exit-0 PROM branch remains" 1 "$(grep -q 'PROM_URL not set — canary SLO watch skipped' "$CD"; echo $?)"
chk "canary: creates real GitHub Deployment"     0 "$(grep -q 'repos/\$REPO/deployments' "$CD"; echo $?)"
chk "canary: posts deployment_status success"    0 "$(grep -q 'state=success' "$CD"; echo $?)"
chk "canary: posts deployment_status failure"    0 "$(grep -q 'state=failure' "$CD"; echo $?)"

# 3. gate step behaves (execute the extracted run block)
gate=$(awk '/name: Refuse to run unwired/,/^      - uses/' "$CD" | sed -n '/run: |/,/^      -/p' | sed '1d;$d' | sed 's/^          //')
rc_unwired=$(DEPLOY_WIRED="" bash -c "$gate" >/dev/null 2>&1; echo $?)
rc_wired=$(DEPLOY_WIRED=true bash -c "$gate" >/dev/null 2>&1; echo $?)
chk "gate script: unwired exits 1" 1 "$rc_unwired"
chk "gate script: wired exits 0"   0 "$rc_wired"

# 4. issue-lifecycle: deployment_status now resolves the spec issue via sha → merged PR
T=$(mktemp -d); cd "$T"; mkdir bin
cat > bin/gh <<'GH'
#!/bin/bash
# stub: commits/<sha>/pulls
echo '[{"merged_at":"2026-06-01T00:00:00Z","body":"Ship it\n\nCloses #42"},{"merged_at":null,"body":"Closes #99"}]'
GH
chmod +x bin/gh; export PATH="$T/bin:$PATH"
resolve=$(sed -n '/issue=""/,/echo "issue=\$issue"/p' "$SG/.github/workflows/issue-lifecycle.yml" | sed 's/^          //')
out=$(EVENT=deployment_status DEPLOY_SHA=abc123 DISPATCH_ISSUE= PR_BODY= REPO=o/r GITHUB_OUTPUT=/dev/null bash -c "$resolve" 2>&1; true)
issue=$(EVENT=deployment_status DEPLOY_SHA=abc123 DISPATCH_ISSUE= PR_BODY= REPO=o/r GITHUB_OUTPUT="$T/go" bash -c "$resolve" >/dev/null 2>&1; grep -o '[0-9]*' "$T/go" | head -1)
chk "lifecycle: deployment_status resolves #42 via merged PR" 42 "$issue"
issue=$(EVENT=deployment_status DEPLOY_SHA=abc123 DISPATCH_ISSUE=7 PR_BODY= REPO=o/r GITHUB_OUTPUT="$T/go2" bash -c "$resolve" >/dev/null 2>&1; grep -o '[0-9]*' "$T/go2" | head -1)
chk "lifecycle: dispatch issue still wins"                    7 "$issue"
issue=$(EVENT=pull_request DEPLOY_SHA= DISPATCH_ISSUE= PR_BODY='Fixes #13' REPO=o/r GITHUB_OUTPUT="$T/go3" bash -c "$resolve" >/dev/null 2>&1; grep -o '[0-9]*' "$T/go3" | head -1)
chk "lifecycle: PR-body path unchanged"                       13 "$issue"
cd /; rm -rf "$T"

# 5. doctor flags the stub; release agent bans fake "Deployed: yes"
cd "$R"
out=$(bash .claude/scripts/harness-doctor.sh 2>/dev/null)
chk "doctor: deploy-stub check present (warn unwired)" 0 "$(echo "$out" | grep -q 'deploy stub'; echo $?)"
chk "release agent: NOT WIRED rule"        0 "$(grep -q 'NOT WIRED' "$SG/.claude/agents/specialists/release.md"; echo $?)"
chk "release agent: gh run watch demoted"  0 "$(grep -q 'NOT deploy evidence' "$SG/.claude/agents/specialists/release.md"; echo $?)"
chk "docs: deployment_status checklist"    0 "$(grep -q 'SHIPPED never fires' docs/DEPLOY-INTEGRATION.md; echo $?)"

echo "----"; echo "deploy-gate matrix: $pass pass / $fail fail"
[ "$fail" -eq 0 ]
