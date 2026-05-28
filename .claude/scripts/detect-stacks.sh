#!/usr/bin/env bash
# Detect tech stacks in this repo by scanning for lockfiles + manifest files.
# Round 8 B + E (shared). Outputs JSON: {"stacks":[...],"primary":"..."}.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

stacks=()

# Language/runtime stacks
[ -f package.json ] && stacks+=('"typescript"')
{ [ -f pyproject.toml ] || [ -f requirements.txt ] || [ -f setup.py ]; } && stacks+=('"python"')
[ -f Cargo.toml ] && stacks+=('"rust"')
[ -f go.mod ] && stacks+=('"go"')
{ [ -f pom.xml ] || [ -f build.gradle ] || [ -f build.gradle.kts ]; } && stacks+=('"java"')
{ [ -f Gemfile ]; } && stacks+=('"ruby"')

# Infra / config stacks
find . -maxdepth 4 -name '*.tf' -not -path '*/.terraform/*' -not -path '*/node_modules/*' -print -quit 2>/dev/null | grep -q . && stacks+=('"terraform"')
find . -maxdepth 4 -name 'Dockerfile*' -not -path '*/node_modules/*' -print -quit 2>/dev/null | grep -q . && stacks+=('"docker"')
find . -maxdepth 4 -name '*.yml' -o -name '*.yaml' 2>/dev/null | grep -qE 'k8s|kubernetes|helm' && stacks+=('"kubernetes"')

# Shell + SQL
find . -maxdepth 3 -name '*.sh' -not -path '*/node_modules/*' -not -path '*/.git/*' -print -quit 2>/dev/null | grep -q . && stacks+=('"shell"')
find . -maxdepth 4 -name '*.sql' -not -path '*/node_modules/*' -print -quit 2>/dev/null | grep -q . && stacks+=('"sql"')

# Primary = first detected (heuristic; ordered to prefer the most-common dominant stack)
primary="${stacks[0]:-\"unknown\"}"

# Emit JSON
IFS=','
printf '{"stacks":[%s],"primary":%s}\n' "${stacks[*]:-}" "$primary"
