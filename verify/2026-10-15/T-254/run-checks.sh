#!/usr/bin/env bash
set -u
out=verify/2026-10-15/T-254
printf '0\tbash .claude/scripts/test/factory-intake-adoption.sh upgrade (characterization green.log; Homebrew Python 3.14.4)\n' > "$out/manifest.tsv"
PATH=/opt/homebrew/bin:$PATH bash .claude/scripts/test/factory-intake-adoption.sh package > "$out/package.log" 2>&1
printf '%s\t%s\n' "$?" 'bash .claude/scripts/test/factory-intake-adoption.sh package (compatibility)' >> "$out/manifest.tsv"
PATH=/opt/homebrew/bin:$PATH bash .claude/scripts/test/factory-adopt.sh > "$out/existing-adopt.log" 2>&1
printf '%s\t%s\n' "$?" 'bash .claude/scripts/test/factory-adopt.sh (once)' >> "$out/manifest.tsv"
bash -n .claude/scripts/test/factory-intake-adoption.sh > "$out/bash-syntax.log" 2>&1
printf '%s\t%s\n' "$?" 'bash -n .claude/scripts/test/factory-intake-adoption.sh' >> "$out/manifest.tsv"
git diff --check > "$out/diff-check.log" 2>&1
printf '%s\t%s\n' "$?" 'git diff --check' >> "$out/manifest.tsv"
bash .claude/scripts/validate.sh > "$out/validate.log" 2>&1
printf '%s\t%s\n' "$?" 'bash .claude/scripts/validate.sh' >> "$out/manifest.tsv"
shasum -a 256 .claude/scripts/factory-adopt.py .claude/scripts/test/factory-intake-adoption.sh > "$out/source-sha256.txt"
cat "$out/manifest.tsv"
