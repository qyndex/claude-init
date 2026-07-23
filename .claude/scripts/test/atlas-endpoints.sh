#!/usr/bin/env bash
# M-09a — Atlas v2 ENDPOINTS scraper (route-table inventory).
#
# AC-1: given a repo with Flask/FastAPI, Express, and Next.js route sources
# (each gated by its sentinel), atlas-endpoints.sh writes
# .claude/memory/atlas/ENDPOINTS.md with a generated table (method, path,
# handler file:line) between BEGIN/END markers, one row per discovered route.
#
# Hermetic: builds a throwaway repo in $TMPDIR with fixture route files, runs
# the scraper against it (SCRAPER accepts the target root as $1), and asserts
# the emitted table. No network, no dependence on this repo's own stack.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRAPER="$ROOT/.claude/scripts/atlas-endpoints.sh"

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }

test -f "$SCRAPER" || { echo "scraper missing: $SCRAPER"; echo "passed: 0"; echo "failed: 1"; exit 1; }

# ─── Build a hermetic multi-stack fixture repo ──────────────────────────────
repo="$(mktemp -d)"
trap 'rm -rf "$repo"' EXIT

# Flask/FastAPI sentinel + routes
: > "$repo/requirements.txt"
mkdir -p "$repo/api"
cat > "$repo/api/views.py" <<'PY'
from flask import Blueprint
bp = Blueprint("bp", __name__)

@app.route("/health")
def health():
    return "ok"

@app.post("/users")
def create_user():
    return "", 201

@router.get("/items/{item_id}")
def read_item(item_id: int):
    return {"id": item_id}
PY

# Express sentinel + routes
cat > "$repo/package.json" <<'JSON'
{ "name": "fixture", "dependencies": { "express": "4.19.2" } }
JSON
mkdir -p "$repo/src"
cat > "$repo/src/server.js" <<'JS'
const app = require('express')();
const router = require('express').Router();
app.get('/ping', (req, res) => res.send('pong'));
router.post('/login', (req, res) => res.sendStatus(200));
app.delete('/session', (req, res) => res.sendStatus(204));
JS

# Next.js sentinel + file-based routes (App Router + Pages Router)
: > "$repo/next.config.mjs"
mkdir -p "$repo/app/orders/[id]" "$repo/pages/api/webhooks"
cat > "$repo/app/orders/[id]/route.ts" <<'TS'
export async function GET() { return Response.json({}); }
export async function PATCH() { return Response.json({}); }
TS
cat > "$repo/pages/api/webhooks/stripe.js" <<'JS'
export default function handler(req, res) { res.status(200).end(); }
JS

# ─── Run the scraper against the fixture repo ───────────────────────────────
out="$("$SCRAPER" "$repo" 2>&1)"; rc=$?
check "scraper exits 0" "$rc"

ENDPOINTS="$repo/.claude/memory/atlas/ENDPOINTS.md"
test -f "$ENDPOINTS"; check "ENDPOINTS.md is written" $?
body="$(cat "$ENDPOINTS" 2>/dev/null || true)"

# ─── Markers ────────────────────────────────────────────────────────────────
printf '%s' "$body" | grep -qF '<!-- BEGIN:endpoints (generated) -->'
check "has BEGIN marker" $?
printf '%s' "$body" | grep -qF '<!-- END:endpoints -->'
check "has END marker" $?

# ─── Flask/FastAPI rows ─────────────────────────────────────────────────────
printf '%s' "$body" | grep -qE '\|[^|]*GET[^|]*\|[^|]*/health'
check "Flask GET /health row present" $?
printf '%s' "$body" | grep -qE '\|[^|]*POST[^|]*\|[^|]*/users'
check "Flask POST /users row present" $?
printf '%s' "$body" | grep -qE '\|[^|]*GET[^|]*\|[^|]*/items/\{item_id\}'
check "FastAPI GET /items/{item_id} row present" $?

# ─── Express rows ───────────────────────────────────────────────────────────
printf '%s' "$body" | grep -qE '\|[^|]*GET[^|]*\|[^|]*/ping'
check "Express GET /ping row present" $?
printf '%s' "$body" | grep -qE '\|[^|]*POST[^|]*\|[^|]*/login'
check "Express POST /login row present" $?
printf '%s' "$body" | grep -qE '\|[^|]*DELETE[^|]*\|[^|]*/session'
check "Express DELETE /session row present" $?

# ─── Next.js rows (file-based) ──────────────────────────────────────────────
printf '%s' "$body" | grep -qE '\|[^|]*GET[^|]*\|[^|]*/orders/\[id\]'
check "Next App-Router GET /orders/[id] row present" $?
printf '%s' "$body" | grep -qE '\|[^|]*PATCH[^|]*\|[^|]*/orders/\[id\]'
check "Next App-Router PATCH /orders/[id] row present" $?
printf '%s' "$body" | grep -qE '\|[^|]*/api/webhooks/stripe'
check "Next Pages-Router /api/webhooks/stripe row present" $?

# ─── file:line provenance present in at least one row ───────────────────────
printf '%s' "$body" | grep -qE 'api/views\.py:[0-9]+'
check "row carries handler file:line provenance" $?

# ─── Empty-but-valid path: repo with NO sentinels ───────────────────────────
empty="$(mktemp -d)"
"$SCRAPER" "$empty" >/dev/null 2>&1; erc=$?
check "scraper exits 0 on stack-less repo" "$erc"
empty_body="$(cat "$empty/.claude/memory/atlas/ENDPOINTS.md" 2>/dev/null || true)"
printf '%s' "$empty_body" | grep -qF '<!-- BEGIN:endpoints (generated) -->'
check "stack-less repo still emits BEGIN marker" $?
printf '%s' "$empty_body" | grep -qiE 'no (http )?routes|no endpoints'
check "stack-less repo emits an empty-but-valid note" $?
rm -rf "$empty"

echo "passed: $pass"
echo "failed: $fail"
[ "$fail" -eq 0 ]
