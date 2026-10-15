#!/usr/bin/env bash
set -u
out=verify/2026-10-16/T-256
printf '0\tbash .claude/scripts/test/factory-intake-adoption.sh rollback-observability (ledger GREEN; bundled crypto Python3.12.14)\n' > "$out/manifest.tsv"
for selector in authenticated edits-replay publication checkpoint checkpoint-failure; do
 PATH=/Users/shravanjha/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin:$PATH bash .claude/scripts/test/factory-intake-slack.sh "$selector" > "$out/slack-$selector.log" 2>&1
 printf '%s\t%s\n' "$?" "bash .claude/scripts/test/factory-intake-slack.sh $selector (bundled crypto Python)" >> "$out/manifest.tsv"
done
for suite in factory-hosted-feedback factory-encrypted-feedback; do
 PATH=/Users/shravanjha/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin:$PATH bash ".claude/scripts/test/$suite.sh" > "$out/$suite.log" 2>&1
 printf '%s\t%s\n' "$?" "bash .claude/scripts/test/$suite.sh (bundled crypto Python)" >> "$out/manifest.tsv"
done
for selector in urgent-control approval-eligibility; do
 PATH=/opt/homebrew/bin:$PATH bash .claude/scripts/test/factory-request-intake.sh "$selector" > "$out/local-$selector.log" 2>&1
 printf '%s\t%s\n' "$?" "bash .claude/scripts/test/factory-request-intake.sh $selector (Homebrew Python3.14.4)" >> "$out/manifest.tsv"
done
bash -n .claude/scripts/test/factory-intake-adoption.sh > "$out/bash-syntax.log" 2>&1
printf '%s\t%s\n' "$?" 'bash -n .claude/scripts/test/factory-intake-adoption.sh' >> "$out/manifest.tsv"
git diff --check > "$out/diff-check.log" 2>&1
printf '%s\t%s\n' "$?" 'git diff --check' >> "$out/manifest.tsv"
bash .claude/scripts/validate.sh > "$out/validate.log" 2>&1
printf '%s\t%s\n' "$?" 'bash .claude/scripts/validate.sh' >> "$out/manifest.tsv"
shasum -a 256 .claude/scripts/factory-intake.py .claude/scripts/test/factory-intake-adoption.sh docs/FACTORY-REQUEST-INTAKE.md > "$out/source-sha256.txt"
cat "$out/manifest.tsv"
