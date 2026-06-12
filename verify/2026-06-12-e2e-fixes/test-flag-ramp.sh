#!/usr/bin/env bash
# E2E: P4.9 release-deploy-2,3,4 — rollback-flag adapters, ramp-check driver, auto-merge policy
set -u
R=/Volumes/M/sourcecode/qyndex/claude-init
SG="$R/verify/2026-06-12-e2e-fixes/staged"
pass=0; fail=0
chk() { local d=$1 e=$2 a=$3; if [ "$e" = "$a" ]; then echo "PASS: $d"; pass=$((pass+1)); else echo "FAIL: $d (want $e got $a)"; fail=$((fail+1)); fi; }

mkroot() {
  T=$(mktemp -d); cd "$T"
  mkdir -p .claude/scripts/lib .claude/memory/flags .claude/memory/playbooks specs/active tasks bin
  cp "$R/.claude/scripts/rollback-flag.sh" "$R/.claude/scripts/ramp-check.sh" .claude/scripts/
  cp -R "$R/.claude/scripts/lib/." .claude/scripts/lib/
  printf '# Tasks\n\n## Active\n\n## Archive\n' > tasks/TASKS.md
  # stub curl: prom queries get JSON (rate from $PROM_RATE); everything else logs + exits $CURL_RC
  cat > bin/curl <<'CURL'
#!/bin/bash
if printf '%s' "$*" | grep -q 'api/v1/query'; then
  echo "{\"data\":{\"result\":[{\"value\":[0,\"${PROM_RATE:-0}\"]}]}}"
else
  echo "$*" >> "${CURL_LOG:-/dev/null}"
  exit "${CURL_RC:-0}"
fi
CURL
  cat > bin/gh <<'GH'
#!/bin/bash
echo "$*" >> "${GH_LOG:-/dev/null}"
exit "${GH_RC:-0}"
GH
  printf '#!/bin/bash\necho "$1 $2" >> "${RAMP_LOG:-/dev/null}"\nexit "${RAMP_RC:-0}"\n' > bin/rampstub
  chmod +x bin/curl bin/gh bin/rampstub
  export PATH="$T/bin:$PATH"
}

# ── rollback-flag.sh ──
mkroot
RB=".claude/scripts/rollback-flag.sh"
chk "kill: unwired provider → exit 2"       2 "$(FLAG_PROVIDER= bash $RB myflag >/dev/null 2>&1; echo $?)"
chk "kill: unknown provider → exit 2"       2 "$(FLAG_PROVIDER=zzz bash $RB myflag >/dev/null 2>&1; echo $?)"
chk "kill: bad flag name → exit 1"          1 "$(FLAG_PROVIDER=webhook bash $RB 'my flag;rm' >/dev/null 2>&1; echo $?)"
chk "kill: dry-run → exit 0, no log"        0 "$(FLAG_PROVIDER=webhook FLAG_KILL_WEBHOOK=http://x bash $RB myflag --dry-run >/dev/null 2>&1 && [ ! -f .claude/memory/playbooks/flag-kill-log.md ]; echo $?)"
rc=$(FLAG_PROVIDER=webhook FLAG_KILL_WEBHOOK=http://x CURL_LOG="$T/curl.log" bash $RB myflag --reason "test breach" >/dev/null 2>&1; echo $?)
chk "kill: webhook success → exit 0"        0 "$rc"
chk "kill: webhook called with flag"        0 "$(grep -q 'myflag' "$T/curl.log"; echo $?)"
chk "kill: kill-log appended"               0 "$(grep -q 'rollback-flag myflag' .claude/memory/playbooks/flag-kill-log.md; echo $?)"
chk "kill: registry KILLED row"             0 "$(grep -q 'KILLED' .claude/memory/flags/REGISTRY.md; echo $?)"
chk "kill: failed provider call → exit 2"   2 "$(FLAG_PROVIDER=webhook FLAG_KILL_WEBHOOK=http://x CURL_RC=22 bash $RB other >/dev/null 2>&1; echo $?)"
# --service resolution via spec
printf -- '---\nid: 099\nstatus: approved\n---\nservice: checkout\n\n## Rollout\n  name: checkout_v2_enabled\n' > specs/active/099-checkout.md
out=$(FLAG_PROVIDER=webhook FLAG_KILL_WEBHOOK=http://x bash $RB --service checkout 2>&1); rc=$?
chk "kill: --service resolves spec flag"    0 "$([ $rc = 0 ] && echo "$out" | grep -q 'checkout_v2_enabled'; echo $?)"
chk "kill: --service unmapped → exit 3"     3 "$(FLAG_PROVIDER=webhook FLAG_KILL_WEBHOOK=http://x bash $RB --service nosuch >/dev/null 2>&1; echo $?)"
chk "kill: --service regex chars → exit 1"  1 "$(bash $RB --service 'a|b' >/dev/null 2>&1; echo $?)"
cd /; rm -rf "$T"

# ── ramp-check.sh ──
mkroot
RC_SH=".claude/scripts/ramp-check.sh"
REG=.claude/memory/flags/REGISTRY.md
spec() { printf -- '---\nid: 0%s\nstatus: approved\n---\nservice: svc%s\ngithub_issue: 4%s\n\n## Rollout\n  name: f%s\n  auto_rollback_threshold: 0.01\n' "$1" "$1" "$1" "$1" > "specs/active/00$1-f.md"; }
iso_ago() { date -v-"$1"H -Iseconds 2>/dev/null || date -d "$1 hours ago" -Iseconds; }

# 1: soaked 1% + gate met + ramp cmd wired → ramps to 10
spec 1; printf '# Flag registry\n\n| f1 | 1 | %s | start |\n' "$(iso_ago 25)" > "$REG"
PROM_URL=http://prom PROM_RATE=0.001 FLAG_RAMP_CMD=rampstub RAMP_LOG="$T/ramp.log" bash $RC_SH >/dev/null 2>&1
chk "ramp: gate met after soak → ramped"    0 "$(grep -q 'f1 10' "$T/ramp.log"; echo $?)"
chk "ramp: registry row appended at 10"     0 "$(grep -qE '^\| f1 \| 10 \|' "$REG"; echo $?)"

# 2: not soaked → hold
spec 2; printf '# Flag registry\n\n| f2 | 10 | %s | start |\n' "$(iso_ago 2)" > "$REG"; rm -f "$T/ramp.log"
out=$(PROM_URL=http://prom PROM_RATE=0.001 FLAG_RAMP_CMD=rampstub RAMP_LOG="$T/ramp.log" bash $RC_SH 2>&1)
chk "ramp: mid-soak → hold (no ramp)"       0 "$(echo "$out" | grep -q 'f2: 10% soaking' && [ ! -s "$T/ramp.log" ]; echo $?)"
rm -f specs/active/002-f.md

# 3: gate breach → mechanical kill + loud task
spec 3; printf '# Flag registry\n\n| f3 | 50 | %s | start |\n' "$(iso_ago 80)" > "$REG"
PROM_URL=http://prom PROM_RATE=0.5 FLAG_PROVIDER=webhook FLAG_KILL_WEBHOOK=http://x bash $RC_SH >/dev/null 2>&1
chk "ramp: breach → KILLED in registry"     0 "$(grep -q 'KILLED' "$REG"; echo $?)"
chk "ramp: breach → loud rollback task"     0 "$(grep -q 'rolled back at 50%' tasks/TASKS.md; echo $?)"
rm -f specs/active/003-f.md

# 4: PROM unwired → loud task, no ramp
spec 4; printf '# Flag registry\n\n| f4 | 1 | %s | start |\n' "$(iso_ago 30)" > "$REG"; rm -f "$T/ramp.log"
PROM_URL= FLAG_RAMP_CMD=rampstub RAMP_LOG="$T/ramp.log" bash $RC_SH >/dev/null 2>&1
chk "ramp: PROM unwired → loud task"        0 "$(grep -q 'PROM_URL is unwired' tasks/TASKS.md; echo $?)"
chk "ramp: PROM unwired → no blind ramp"    0 "$([ ! -s "$T/ramp.log" ]; echo $?)"
rm -f specs/active/004-f.md

# 5: ramp provider unwired → loud task
spec 5; printf '# Flag registry\n\n| f5 | 1 | %s | start |\n' "$(iso_ago 30)" > "$REG"
PROM_URL=http://prom PROM_RATE=0.001 bash $RC_SH >/dev/null 2>&1
chk "ramp: provider unwired → loud task"    0 "$(grep -q 'NO ramp provider is wired' tasks/TASKS.md; echo $?)"
rm -f specs/active/005-f.md

# 6: 100% → flag-shipped dispatch + SHIPPED row
spec 6; printf '# Flag registry\n\n| f6 | 100 | %s | start |\n' "$(iso_ago 5)" > "$REG"
GH_LOG="$T/gh.log" bash $RC_SH >/dev/null 2>&1
chk "ramp: 100%% fires flag-shipped"        0 "$(grep -q 'flag-shipped' "$T/gh.log" && grep -q 'issue_number]=46' "$T/gh.log"; echo $?)"
chk "ramp: SHIPPED row recorded"            0 "$(grep -q 'SHIPPED' "$REG"; echo $?)"
GH_LOG="$T/gh2.log" bash $RC_SH >/dev/null 2>&1
chk "ramp: dispatch fires only once"        0 "$([ ! -s "$T/gh2.log" ]; echo $?)"
cd /; rm -rf "$T"

# ── workflows + policy docs (static) ──
cd "$R"
for wf in ramp-check auto-merge hotfix-ingest; do
  chk "staged $wf.yml valid YAML" 0 "$(ruby -ryaml -e "YAML.load_file('$SG/.github/workflows/$wf.yml')" >/dev/null 2>&1; echo $?)"
done
AM="$SG/.github/workflows/auto-merge.yml"
chk "auto-merge: opt-in label condition"    0 "$(grep -q "auto-merge-ok" "$AM"; echo $?)"
chk "auto-merge: overnight branch pattern"  0 "$(grep -q "claude/overnight-" "$AM"; echo $?)"
chk "auto-merge: draft guard"               0 "$(grep -q 'draft == false' "$AM"; echo $?)"
chk "auto-merge: native --auto (gates win)" 0 "$(grep -q -- '--auto --squash' "$AM"; echo $?)"
chk "hotfix: flag first-responder step"     0 "$(grep -q 'Flag first-responder' "$SG/.github/workflows/hotfix-ingest.yml"; echo $?)"
chk "canary: breach path calls rollback"    0 "$(grep -q 'rollback-flag.sh' "$SG/.github/workflows/canary-deploy.yml"; echo $?)"
chk "ship: auto-mode merge policy"          0 "$(grep -q 'auto-merge-ok' "$SG/.claude/skills/ship/SKILL.md"; echo $?)"
chk "release agent: auto-mode policy"       0 "$(grep -q 'auto-merge-ok' "$SG/.claude/agents/specialists/release.md"; echo $?)"
chk "constitution §XI: autonomous merge"    0 "$(grep -q 'Autonomous merge' "$SG/.claude/CLAUDE.md"; echo $?)"
chk "playbook: dead deploy.yml ref fixed"   1 "$(grep -q 'disable deploy.yml' .claude/memory/playbooks/rollback.md; echo $?)"
chk "release-train: no dead deploy.yml run" 1 "$(grep -q 'gh workflow run deploy.yml' "$SG/.claude/skills/release-train/SKILL.md"; echo $?)"

echo "----"; echo "flag-ramp matrix: $pass pass / $fail fail"
[ "$fail" -eq 0 ]
