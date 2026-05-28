#!/usr/bin/env bash
# Atlas refresh — Round 8 C.
#
# Scans the repo + emits .claude/memory/atlas/{STACK.md, STRUCTURE.md,
# KNOWN_ENTRIES.md, manifest.json, .updated}.
#
# Detection rules per .claude/skills/detect-stack/SKILL.md.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# shellcheck source=lib/atomic-write.sh
. "$ROOT/.claude/scripts/lib/atomic-write.sh"

ATLAS=".claude/memory/atlas"
mkdir -p "$ATLAS"

now_iso=$(date -Iseconds)
# JUSTIFIED: git rev-parse stderr suppressed — a non-git dir falls through to the "no-git" literal
git_sha=$(git rev-parse HEAD 2>/dev/null || echo "no-git")

# ─── Detect languages ───────────────────────────────────────────────────
langs=()
[ -f package.json ] && {
  # JUSTIFIED: find stderr suppressed — permission-denied subtrees are skipped; grep -q decides presence
  if find . -maxdepth 3 -name '*.ts' -o -name 'tsconfig.json' 2>/dev/null | grep -q .; then
    langs+=("typescript")
  else
    langs+=("javascript")
  fi
}
{ [ -f pyproject.toml ] || [ -f requirements.txt ] || [ -f setup.py ]; } && langs+=("python")
[ -f Cargo.toml ] && langs+=("rust")
[ -f go.mod ] && langs+=("go")
{ [ -f pom.xml ] || [ -f build.gradle ] || [ -f build.gradle.kts ]; } && langs+=("java")
[ -f Gemfile ] && langs+=("ruby")

# ─── Detect web framework ───────────────────────────────────────────────
web_fw="unknown"
if [ -f next.config.js ] || [ -f next.config.mjs ] || [ -f next.config.ts ]; then
  # JUSTIFIED: find stderr suppressed — permission-denied subtrees are skipped; grep -q decides App-Router presence
  if [ -d app ] || find . -maxdepth 3 -name 'app' -type d -not -path '*/node_modules/*' -print -quit 2>/dev/null | grep -q .; then
    web_fw="Next.js (App Router)"
  else
    web_fw="Next.js (Pages Router)"
  fi
elif [ -f remix.config.js ] || [ -f remix.config.mjs ]; then
  web_fw="Remix"
elif [ -f astro.config.mjs ] || [ -f astro.config.ts ]; then
  web_fw="Astro"
elif [ -f svelte.config.js ]; then
  web_fw="SvelteKit"
elif [ -f vue.config.js ] || [ -f nuxt.config.ts ]; then
  web_fw="Vue/Nuxt"
elif [ -f angular.json ]; then
  web_fw="Angular"
elif [ -f vite.config.ts ] || [ -f vite.config.js ]; then
  web_fw="Vite"
fi

# ─── Detect API framework ───────────────────────────────────────────────
api_fw="unknown"
if [ -f package.json ]; then
  # JUSTIFIED: grep stderr suppressed across this block — a missing dependency name is a non-match, the documented "framework not present" case
  if grep -q '"@trpc/server"' package.json 2>/dev/null; then api_fw="tRPC"
  elif grep -q '"@nestjs/core"' package.json 2>/dev/null; then api_fw="NestJS"
  elif grep -q '"fastify"' package.json 2>/dev/null; then api_fw="Fastify"
  # JUSTIFIED: grep error output discarded — an absent dependency is a non-match, the documented "framework not present" case
  elif grep -q '"express"' package.json 2>/dev/null; then api_fw="Express"
  elif grep -q '"hono"' package.json 2>/dev/null; then api_fw="Hono"
  fi
fi
if [ -f pyproject.toml ]; then
  # JUSTIFIED: grep stderr suppressed — a missing dependency name is a non-match, the documented "framework not present" case
  if grep -q 'fastapi' pyproject.toml 2>/dev/null; then api_fw="FastAPI"
  elif grep -q '"django"' pyproject.toml 2>/dev/null; then api_fw="Django"
  elif grep -q '"flask"' pyproject.toml 2>/dev/null; then api_fw="Flask"
  fi
fi
if [ -f go.mod ]; then
  # JUSTIFIED: grep stderr suppressed — a missing require line is a non-match, the documented "framework not present" case
  if grep -q 'gin-gonic/gin' go.mod 2>/dev/null; then api_fw="Gin"
  elif grep -q 'gofiber/fiber' go.mod 2>/dev/null; then api_fw="Fiber"
  fi
fi
if [ -f Cargo.toml ]; then
  # JUSTIFIED: grep stderr suppressed — a missing crate dependency is a non-match, the documented "framework not present" case
  if grep -q '^axum' Cargo.toml 2>/dev/null; then api_fw="Axum"
  elif grep -q '^actix-web' Cargo.toml 2>/dev/null; then api_fw="Actix"
  fi
fi

# ─── Detect ORM ─────────────────────────────────────────────────────────
orm="none"
[ -f prisma/schema.prisma ] && orm="Prisma"
[ -f drizzle.config.ts ] || [ -f drizzle.config.mjs ] && orm="Drizzle"
# JUSTIFIED: grep stderr suppressed — silences "No such file" when package.json is absent; a non-match leaves orm unchanged
grep -q '^typeorm' package.json 2>/dev/null && orm="TypeORM"
# JUSTIFIED: grep stderr suppressed — silences "No such file" when pyproject.toml/requirements.txt are absent; non-match leaves orm unchanged
grep -q 'sqlalchemy' pyproject.toml requirements.txt 2>/dev/null && orm="SQLAlchemy"
[ -f alembic.ini ] && orm="Alembic"

# ─── Detect monorepo tool ───────────────────────────────────────────────
mono="no"
[ -f turbo.json ] && mono="Turborepo"
[ -f nx.json ] && mono="Nx"
[ -f pnpm-workspace.yaml ] && mono="pnpm-workspaces"
[ -f lerna.json ] && mono="Lerna"

# ─── Detect test frameworks ─────────────────────────────────────────────
tests=()
[ -f vitest.config.ts ] || [ -f vitest.config.js ] && tests+=("vitest")
[ -f jest.config.ts ] || [ -f jest.config.js ] && tests+=("jest")
[ -f playwright.config.ts ] || [ -f playwright.config.js ] && tests+=("playwright")
[ -f cypress.config.ts ] && tests+=("cypress")
# JUSTIFIED: grep stderr suppressed — silences "No such file" when pyproject.toml is absent; non-match means pytest not configured
[ -f pytest.ini ] || grep -q '^\[tool.pytest' pyproject.toml 2>/dev/null && tests+=("pytest")
[ -f go.mod ] && tests+=("go test")
[ -f Cargo.toml ] && tests+=("cargo test")

# ─── Write STACK.md ─────────────────────────────────────────────────────
{
  echo "# Detected stack"
  echo
  echo "_Auto-generated by .claude/scripts/atlas-refresh.sh — Round 8 C._"
  echo "_Refresh: \`bash .claude/scripts/atlas-refresh.sh\` or \`/atlas refresh\`_"
  echo
  echo "**Last updated**: $now_iso"
  echo "**Git SHA**: $git_sha"
  echo
  echo "## Languages"
  for l in "${langs[@]+"${langs[@]}"}"; do echo "- $l"; done
  echo
  echo "## Frameworks"
  echo "- Web: $web_fw"
  echo "- API: $api_fw"
  echo "- ORM: $orm"
  echo
  echo "## Monorepo"
  echo "- Tool: $mono"
  echo
  echo "## Test frameworks"
  for t in "${tests[@]+"${tests[@]}"}"; do echo "- $t"; done
  echo
  echo "## Idioms (auto-extracted; edit as needed)"
  if [ "$web_fw" = "Next.js (App Router)" ]; then
    echo "- Use Server Components by default; opt into Client Components with 'use client'"
    echo "- Server Actions for mutations (no separate API route for simple writes)"
    echo "- Loading + error boundaries via loading.tsx + error.tsx"
  fi
  if [ "$api_fw" = "tRPC" ]; then
    echo "- Type-safe client calls via @trpc/client — no fetch() in components"
    echo "- Procedures live in routers/; auth via middleware"
  fi
  if [ "$orm" = "Prisma" ]; then
    echo "- Run \`prisma migrate dev\` after every schema.prisma change"
    echo "- Use \`prisma db push\` only for prototyping; migrations for prod"
  fi
} > "$ATLAS/STACK.md"

# ─── Write STRUCTURE.md ─────────────────────────────────────────────────
{
  echo "# Repo structure"
  echo
  echo "Top-level layout. Auto-generated by atlas-refresh."
  echo
  echo "**Last updated**: $now_iso"
  echo
  # JUSTIFIED: ls stderr suppressed — an empty repo with no subdirectories yields no output and the loop simply skips
  for d in $(ls -d */ 2>/dev/null | head -20); do
    d_clean="${d%/}"
    # Skip noise
    case "$d_clean" in
      node_modules|.git|.next|dist|build|target|.terraform|.cache) continue ;;
    esac
    # Describe based on conventional names + content
    desc="unknown"
    case "$d_clean" in
      src) desc="primary source code" ;;
      app|apps) desc="application code (monorepo or Next.js App Router)" ;;
      packages) desc="monorepo packages" ;;
      lib|libs) desc="shared library code" ;;
      components) desc="React components" ;;
      pages) desc="Next.js Pages Router routes" ;;
      api) desc="API handlers" ;;
      server) desc="server-side code" ;;
      db|database) desc="database scripts + schema" ;;
      prisma) desc="Prisma schema + migrations" ;;
      migrations) desc="database migrations" ;;
      tests|test|__tests__) desc="test files (non-colocated)" ;;
      e2e) desc="E2E Playwright tests" ;;
      docs) desc="documentation" ;;
      scripts) desc="utility scripts" ;;
      infra|terraform) desc="infrastructure-as-code" ;;
      .github) desc="GitHub Actions workflows + config" ;;
      .claude) desc="Claude Code harness — agents, skills, hooks, memory" ;;
      specs) desc="feature specifications" ;;
      plans) desc="technical plans" ;;
      tasks) desc="task ledger" ;;
      initiatives) desc="multi-quarter program artifacts" ;;
      pivots) desc="strategic pivot manifests (Round 7 B)" ;;
      verify) desc="verification artifacts (screenshots, reports)" ;;
    esac
    # JUSTIFIED: find stderr suppressed — permission-denied entries are excluded from the count, which is a display-only file tally
    file_count=$(find "$d_clean" -type f 2>/dev/null | wc -l | tr -d ' ')
    echo "- **$d_clean/** ($file_count files) — $desc"
  done
} > "$ATLAS/STRUCTURE.md"

# ─── Write KNOWN_ENTRIES.md ─────────────────────────────────────────────
{
  echo "# Known entry points"
  echo
  echo "Well-known paths for surgical changes. Auto-discovered."
  echo
  echo "## Build/config"
  for f in package.json pyproject.toml Cargo.toml go.mod next.config.js tsconfig.json vite.config.ts; do
    [ -f "$f" ] && echo "- \`$f\`"
  done
  echo
  echo "## Database"
  for f in prisma/schema.prisma drizzle.config.ts alembic.ini; do
    [ -f "$f" ] && echo "- \`$f\`"
  done
  # JUSTIFIED: find stderr suppressed — permission-denied subtrees are skipped; an empty result means no migrations dir, handled by the -n test below
  migrations_dir=$(find . -maxdepth 3 -name 'migrations' -type d -not -path '*/node_modules/*' 2>/dev/null | head -1)
  [ -n "$migrations_dir" ] && echo "- Migrations: \`$migrations_dir\`"
  echo
  echo "## API / routes (heuristic)"
  for d in app pages src/api api routes; do
    [ -d "$d" ] && echo "- Route root: \`$d/\`"
  done
  echo
  echo "## Tests"
  for d in tests test __tests__ e2e; do
    [ -d "$d" ] && echo "- \`$d/\`"
  done
} > "$ATLAS/KNOWN_ENTRIES.md"

# ─── Write manifest.json (machine-readable) ────────────────────────────
langs_json='[]'
tests_json='[]'
[ "${#langs[@]:-0}" -gt 0 ] && langs_json=$(printf '%s\n' "${langs[@]+"${langs[@]}"}" | jq -R . | jq -sc .)
[ "${#tests[@]:-0}" -gt 0 ] && tests_json=$(printf '%s\n' "${tests[@]+"${tests[@]}"}" | jq -R . | jq -sc .)

jq -nc \
  --arg now "$now_iso" \
  --arg sha "$git_sha" \
  --argjson languages "$langs_json" \
  --arg web_fw "$web_fw" \
  --arg api_fw "$api_fw" \
  --arg orm "$orm" \
  --arg mono "$mono" \
  --argjson tests "$tests_json" \
  --arg primary "${langs[0]:-unknown}" \
  '{
    updated_at: $now,
    git_sha: $sha,
    languages: $languages,
    frameworks: { web: $web_fw, api: $api_fw, orm: $orm },
    monorepo_tool: $mono,
    test_frameworks: $tests,
    primary_stack: $primary
  }' | replace_atomic "$ATLAS/manifest.json"

# ─── Write .updated marker ─────────────────────────────────────────────
cat > "$ATLAS/.updated" <<EOF
{"updated_at": "$now_iso", "git_sha": "$git_sha"}
EOF

# Clear any dirty marker since we just refreshed
rm -f "$ATLAS/.dirty"

echo "✓ Atlas refreshed at $ATLAS/"
echo "  Languages: ${langs[*]:-none}"
echo "  Web: $web_fw | API: $api_fw | ORM: $orm | Monorepo: $mono"
