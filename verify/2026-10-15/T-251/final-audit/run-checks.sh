#!/usr/bin/env bash
set -u
export PATH=/Users/shravanjha/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin:$PATH
out=verify/2026-10-15/T-251/final-audit
mkdir -p "$out"
: > "$out/manifest.tsv"
for selector in checkpoint-failure checkpoint publication authenticated edits-replay; do
 bash .claude/scripts/test/factory-intake-slack.sh "$selector" > "$out/intake-$selector.log" 2>&1
 printf '%s\t%s\n' "$?" "bash .claude/scripts/test/factory-intake-slack.sh $selector" >> "$out/manifest.tsv"
done
for name in factory-feedback factory-legacy-feedback factory-slack-feedback factory-hosted-feedback factory-encrypted-feedback; do
 bash ".claude/scripts/test/$name.sh" > "$out/$name.log" 2>&1
 printf '%s\t%s\n' "$?" "bash .claude/scripts/test/$name.sh" >> "$out/manifest.tsv"
done
bash .claude/scripts/validate.sh > "$out/validate.log" 2>&1
printf '%s\t%s\n' "$?" 'bash .claude/scripts/validate.sh' >> "$out/manifest.tsv"
git diff --check > "$out/diff-check.log" 2>&1
printf '%s\t%s\n' "$?" 'git diff --check' >> "$out/manifest.tsv"
cat "$out/manifest.tsv"
