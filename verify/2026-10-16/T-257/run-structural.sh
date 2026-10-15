#!/usr/bin/env bash
set -u
out=verify/2026-10-16/T-257
bash -n .claude/scripts/test/factory-intake-adoption.sh > "$out/bash-syntax.log" 2>&1
printf '%s\t%s\n' "$?" 'bash -n .claude/scripts/test/factory-intake-adoption.sh' > "$out/structural-manifest.tsv"
git diff --check > "$out/diff-check.log" 2>&1
printf '%s\t%s\n' "$?" 'git diff --check' >> "$out/structural-manifest.tsv"
bash .claude/scripts/validate.sh > "$out/validate.log" 2>&1
printf '%s\t%s\n' "$?" 'bash .claude/scripts/validate.sh' >> "$out/structural-manifest.tsv"
shasum -a 256 .claude/scripts/test/factory-intake-adoption.sh docs/FACTORY-REQUEST-INTAKE.md > "$out/source-sha256.txt"
cat "$out/structural-manifest.tsv"
