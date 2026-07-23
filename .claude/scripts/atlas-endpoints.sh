#!/usr/bin/env bash
# Atlas v2 — ENDPOINTS scraper (M-09a).
#
# Scans a repo for HTTP route definitions and writes an inventory table
# (method | path | handler file:line) into
# .claude/memory/atlas/ENDPOINTS.md, between generated markers.
#
# Stacks (each gated by a sentinel so we only scan what's present):
#   Flask/FastAPI (Python)  — requirements.txt / pyproject.toml / setup.py
#     @app.route / @app.get|post|... / @router.get|... / @bp.route(...)
#   Express (JS/TS)         — package.json depending on "express"
#     app.get('/x' / router.post('/y' / etc.
#   Next.js (file-based)    — next.config.{js,mjs,ts}
#     app/**/route.ts (App Router) + pages/api/** (Pages Router)
#
# Standalone: not wired into any hook. Target repo defaults to this repo's
# root but may be passed as $1 (used by the hermetic test).

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TARGET="${1:-$ROOT}"
TARGET="$(cd "$TARGET" && pwd)"

ATLAS="$TARGET/.claude/memory/atlas"
OUT="$ATLAS/ENDPOINTS.md"
mkdir -p "$ATLAS"

now_iso=$(date -Iseconds)

# rows accumulate as "method\tpath\tfile:line" lines
rows_file="$(mktemp)"
trap 'rm -f "$rows_file"' EXIT

add_row() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$rows_file"; }

# rel <abs> → path relative to TARGET (portable; no realpath --relative-to)
rel() { printf '%s' "${1#"$TARGET"/}"; }

# ─── Flask / FastAPI (Python) ───────────────────────────────────────────────
if [ -f "$TARGET/requirements.txt" ] || [ -f "$TARGET/pyproject.toml" ] || [ -f "$TARGET/setup.py" ]; then
  # JUSTIFIED: find stderr suppressed — permission-denied subtrees are skipped, not scanned
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    # grep -n gives "LINE:content"; parse decorator forms.
    while IFS=: read -r ln content; do
      # @app.route("/x", methods=["GET","POST"])  or default GET
      if printf '%s' "$content" | grep -qE '\.route\('; then
        path=$(printf '%s' "$content" | sed -nE 's/.*\.route\([[:space:]]*["'"'"']([^"'"'"']+)["'"'"'].*/\1/p')
        [ -n "$path" ] || continue
        methods=$(printf '%s' "$content" | grep -oiE 'methods[[:space:]]*=[[:space:]]*\[[^]]*\]' | grep -oiE '"[A-Z]+"|'"'"'[A-Z]+'"'"'' | tr -d "\"'" | tr '\n' ',' | sed 's/,$//')
        [ -n "$methods" ] || methods="GET"
        IFS=','; for m in $methods; do add_row "$(printf '%s' "$m" | tr '[:lower:]' '[:upper:]')" "$path" "$(rel "$f"):$ln"; done; unset IFS
      # @app.get("/x") / @router.post("/y") / @bp.delete("/z")
      elif printf '%s' "$content" | grep -qiE '\.(get|post|put|patch|delete|options|head)\([[:space:]]*["'"'"']'; then
        m=$(printf '%s' "$content" | sed -nE 's/.*\.(get|post|put|patch|delete|options|head)\(.*/\1/Ip' | head -1)
        path=$(printf '%s' "$content" | sed -nE 's/.*\.(get|post|put|patch|delete|options|head)\([[:space:]]*["'"'"']([^"'"'"']+)["'"'"'].*/\2/Ip')
        [ -n "$path" ] || continue
        add_row "$(printf '%s' "$m" | tr '[:lower:]' '[:upper:]')" "$path" "$(rel "$f"):$ln"
      fi
    done < <(grep -nE '\.(route|get|post|put|patch|delete|options|head)\(' "$f" 2>/dev/null)
  done < <(find "$TARGET" -type f -name '*.py' -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null)
fi

# ─── Express (JS/TS) ────────────────────────────────────────────────────────
if [ -f "$TARGET/package.json" ] && grep -q '"express"' "$TARGET/package.json" 2>/dev/null; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    while IFS=: read -r ln content; do
      # (app|router|<var>).get('/path'   — first string arg is the path
      m=$(printf '%s' "$content" | sed -nE 's/.*[A-Za-z_][A-Za-z0-9_]*\.(get|post|put|patch|delete|options|head|all)\(.*/\1/Ip' | head -1)
      path=$(printf '%s' "$content" | sed -nE 's/.*[A-Za-z_][A-Za-z0-9_]*\.(get|post|put|patch|delete|options|head|all)\([[:space:]]*["'"'"'`]([^"'"'"'`]+)["'"'"'`].*/\2/Ip')
      [ -n "$m" ] && [ -n "$path" ] || continue
      add_row "$(printf '%s' "$m" | tr '[:lower:]' '[:upper:]')" "$path" "$(rel "$f"):$ln"
    done < <(grep -nE '\.(get|post|put|patch|delete|options|head|all)\([[:space:]]*["'"'"'`]/' "$f" 2>/dev/null)
  done < <(find "$TARGET" -type f \( -name '*.js' -o -name '*.ts' -o -name '*.mjs' -o -name '*.cjs' \) -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/app/*' -not -path '*/pages/*' 2>/dev/null)
fi

# ─── Next.js (file-based routing) ───────────────────────────────────────────
if [ -f "$TARGET/next.config.js" ] || [ -f "$TARGET/next.config.mjs" ] || [ -f "$TARGET/next.config.ts" ]; then
  # App Router: app/**/route.{ts,js} — path = dir under app/, methods = exported HTTP fns
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    dir=$(dirname "$f")
    route_path="/${dir#"$TARGET"/app/}"
    [ "$route_path" = "/${dir}" ] && route_path="/"   # file directly under app/
    [ "$route_path" = "//" ] && route_path="/"
    while IFS=: read -r ln content; do
      m=$(printf '%s' "$content" | sed -nE 's/.*function[[:space:]]+(GET|POST|PUT|PATCH|DELETE|OPTIONS|HEAD).*/\1/p' | head -1)
      [ -n "$m" ] || continue
      add_row "$m" "$route_path" "$(rel "$f"):$ln"
    done < <(grep -nE 'export[[:space:]]+(async[[:space:]]+)?function[[:space:]]+(GET|POST|PUT|PATCH|DELETE|OPTIONS|HEAD)' "$f" 2>/dev/null)
  done < <(find "$TARGET/app" -type f \( -name 'route.ts' -o -name 'route.js' \) 2>/dev/null)

  # Pages Router: pages/api/** — one endpoint per file, method ANY
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    api_path="/api/${f#"$TARGET"/pages/api/}"
    api_path="${api_path%.js}"; api_path="${api_path%.ts}"
    api_path="${api_path%/index}"
    add_row "ANY" "$api_path" "$(rel "$f"):1"
  done < <(find "$TARGET/pages/api" -type f \( -name '*.js' -o -name '*.ts' \) 2>/dev/null)
fi

# ─── Emit ENDPOINTS.md ──────────────────────────────────────────────────────
# JUSTIFIED: grep -c exits 1 on zero matches; the || guard yields a clean "0"
row_count=$(grep -c . "$rows_file" 2>/dev/null) || row_count=0

{
  echo "# HTTP endpoint inventory"
  echo
  echo "_Auto-generated by \`.claude/scripts/atlas-endpoints.sh\` (M-09a). Do not edit between the markers._"
  echo
  echo "**Last updated**: $now_iso"
  echo "**Routes found**: $row_count"
  echo
  echo "<!-- BEGIN:endpoints (generated) -->"
  echo
  echo "| Method | Path | Handler |"
  echo "| --- | --- | --- |"
  if [ "$row_count" -gt 0 ]; then
    sort -t"$(printf '\t')" -k2,2 -k1,1 "$rows_file" | while IFS=$'\t' read -r method path handler; do
      echo "| \`$method\` | \`$path\` | \`$handler\` |"
    done
  else
    echo "| _n/a_ | _no routes found_ | _no supported stack sentinel present_ |"
  fi
  echo
  echo "<!-- END:endpoints -->"
} > "$OUT"

echo "✓ Endpoints inventory written: ${OUT#"$TARGET"/} ($row_count routes)"
