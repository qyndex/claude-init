#!/usr/bin/env bash
set -u
out=verify/2026-10-15/T-253
printf '0\tbash .claude/scripts/test/factory-intake-adoption.sh package (ledger green.log; Homebrew Python 3.14)\n' > "$out/manifest.tsv"
PATH=/opt/homebrew/bin:$PATH bash .claude/scripts/test/factory-adopt.sh > "$out/existing-adopt.log" 2>&1
printf '%s\t%s\n' "$?" 'bash .claude/scripts/test/factory-adopt.sh (Homebrew Python)' >> "$out/manifest.tsv"
bash -n .claude/scripts/test/factory-intake-adoption.sh > "$out/bash-syntax.log" 2>&1
printf '%s\t%s\n' "$?" 'bash -n .claude/scripts/test/factory-intake-adoption.sh' >> "$out/manifest.tsv"
git diff --check > "$out/diff-check.log" 2>&1
printf '%s\t%s\n' "$?" 'git diff --check' >> "$out/manifest.tsv"
bash .claude/scripts/validate.sh > "$out/validate.log" 2>&1
printf '%s\t%s\n' "$?" 'bash .claude/scripts/validate.sh' >> "$out/manifest.tsv"
shasum -a 256 .claude/scripts/factory-adopt.py .claude/scripts/test/factory-intake-adoption.sh factory/request-intake.example.json docs/FACTORY-REQUEST-INTAKE.md > "$out/source-sha256.txt"
cat "$out/manifest.tsv"
