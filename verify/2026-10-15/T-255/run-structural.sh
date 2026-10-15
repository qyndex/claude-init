#!/usr/bin/env bash
set -u
out=verify/2026-10-15/T-255
bash -n .claude/scripts/test/factory-request-intake.sh .claude/scripts/test/factory-intake-adoption.sh > "$out/bash-syntax.log" 2>&1
printf '%s\t%s\n' "$?" 'bash -n request-intake.sh intake-adoption.sh' > "$out/structural-manifest.tsv"
git diff --check > "$out/diff-check.log" 2>&1
printf '%s\t%s\n' "$?" 'git diff --check' >> "$out/structural-manifest.tsv"
bash .claude/scripts/validate.sh > "$out/validate.log" 2>&1
printf '%s\t%s\n' "$?" 'bash .claude/scripts/validate.sh' >> "$out/structural-manifest.tsv"
shasum -a 256 .claude/scripts/test/factory-request-intake.sh .claude/scripts/test/factory-intake-adoption.sh .claude/scripts/test/factory-intake-slack.sh > "$out/source-sha256.txt"
cat "$out/structural-manifest.tsv"
