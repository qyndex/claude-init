#!/usr/bin/env bash
# E2E: P4.6 brownfield-1 — adopt-archaeology manifest fail-closed + adopt-state gate-1 refusal
set -u
R=/Volumes/M/sourcecode/qyndex/claude-init
pass=0; fail=0
chk() { local d=$1 e=$2 a=$3; if [ "$e" = "$a" ]; then echo "PASS: $d"; pass=$((pass+1)); else echo "FAIL: $d (want $e got $a)"; fail=$((fail+1)); fi; }

mkrepo() { # mkrepo -> sets $T, cd into it, scaffolds .claude/scripts + git
  T=$(mktemp -d); cd "$T"
  mkdir -p .claude/scripts .claude/state/adopt
  cp "$R/.claude/scripts/adopt-archaeology.sh" "$R/.claude/scripts/adopt-state.sh" .claude/scripts/
  git init -q .; git config user.email t@t; git config user.name t
}

# ── 1. monorepo layout (packages/ + apps/) → globs emitted ──
mkrepo
mkdir -p packages/core apps/web
echo 'export const x=1' > packages/core/i.ts
echo 'export const y=1' > apps/web/a.tsx
git add -A; git commit -qm init
bash .claude/scripts/adopt-archaeology.sh >/dev/null 2>&1
M=.claude/state/adopt/uncharacterized-paths.txt
chk "monorepo: packages/** in manifest" 0 "$(grep -qx 'packages/\*\*' "$M"; echo $?)"
chk "monorepo: apps/** in manifest"     0 "$(grep -qx 'apps/\*\*' "$M"; echo $?)"
cd /; rm -rf "$T"

# ── 2. no conventional root → fail-closed catch-all per source dir + root files ──
mkrepo
mkdir -p weirddir/sub emptydir
echo 'x=1' > weirddir/sub/mod.py
echo 'console.log(1)' > rootonly.js
echo 'doc' > emptydir/readme.txt
git add -A; git commit -qm init
bash .claude/scripts/adopt-archaeology.sh >/dev/null 2>&1
M=.claude/state/adopt/uncharacterized-paths.txt
chk "catch-all: weirddir/** emitted"          0 "$(grep -qx 'weirddir/\*\*' "$M"; echo $?)"
chk "catch-all: emptydir (no source) skipped" 1 "$(grep -qx 'emptydir/\*\*' "$M"; echo $?)"
chk "catch-all: root *.js emitted (js-only)"  0 "$(grep -qx '\*\.js' "$M"; echo $?)"
chk "catch-all: no brace glob emitted"        1 "$(grep -q '{' "$M"; echo $?)"
cd /; rm -rf "$T"

# ── 3. source only under excluded dir (docs/) → empty manifest + hotspots → UNPROTECTED banner ──
mkrepo
mkdir -p docs
echo 'def f(): pass' > docs/gen.py
git add -A; git commit -qm a
echo 'def g(): pass' >> docs/gen.py
git add -A; git commit -qm b
bash .claude/scripts/adopt-archaeology.sh >/dev/null 2>&1
M=.claude/state/adopt/uncharacterized-paths.txt
H=.claude/state/adopt/hotspots.txt
chk "edge: hotspots non-empty"  0 "$([ -s "$H" ]; echo $?)"
chk "edge: manifest glob-empty" 0 "$([ -z "$(grep -vE '^[[:space:]]*(#|$)' "$M")" ] && echo 0 || echo 1)"
chk "edge: UNPROTECTED banner in report" 0 "$(grep -q 'UNPROTECTED' ADOPTION-REPORT.md; echo $?)"

# ── 4. adopt-state gate-1 refusal on the same tree (empty manifest + hotspots) ──
AS=".claude/scripts/adopt-state.sh"
bash "$AS" init . >/dev/null
bash "$AS" set 1 archaeology >/dev/null
touch .claude/state/allow-adopt-approve
out=$(bash "$AS" approve 1 2>&1); rc=$?
chk "gate1: approve 1 REFUSED (empty manifest + hotspots)" 1 "$rc"
chk "gate1: RISK banner printed" 0 "$(echo "$out" | grep -q 'RISK: legacy-safety manifest is EMPTY'; echo $?)"
chk "gate1: marker NOT consumed on refusal" 0 "$([ -f .claude/state/allow-adopt-approve ]; echo $?)"

# populate the manifest → approve passes, marker consumed
echo 'docs/**' >> "$M"
out=$(bash "$AS" approve 1 2>&1); rc=$?
chk "gate1: approve 1 OK once manifest populated" 0 "$rc"
chk "gate1: marker consumed on success" 1 "$([ -f .claude/state/allow-adopt-approve ]; echo $?)"
chk "gate1: approval recorded" 0 "$(jq -e '.approvals["1"]' .claude/state/adopt/STATE.json >/dev/null; echo $?)"

# regression: marker still required at all (no marker → refuse, even with globs)
bash "$AS" set 4 baseline >/dev/null 2>&1
out=$(bash "$AS" approve 4 2>&1); rc=$?
chk "gate4 regression: human-only marker still enforced" 1 "$rc"

# empty manifest but NO hotspots (genuinely no source) → gate-1 check does not fire
mkrepo
git commit -qm empty --allow-empty
bash .claude/scripts/adopt-archaeology.sh >/dev/null 2>&1
bash "$AS" init . >/dev/null; bash "$AS" set 1 archaeology >/dev/null
touch .claude/state/allow-adopt-approve
chk "gate1: empty repo (no hotspots) approves fine" 0 "$(bash "$AS" approve 1 >/dev/null 2>&1; echo $?)"
cd /; rm -rf "$T"

echo "----"; echo "adopt-gate matrix: $pass pass / $fail fail"
[ "$fail" -eq 0 ]
