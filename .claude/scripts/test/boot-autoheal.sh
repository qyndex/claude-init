#!/usr/bin/env bash
# Regression: installed boot hook heals state and throttles repeat work.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.claude/hooks" "$tmp/.claude/scripts" "$tmp/.claude/memory/.cache" \
         "$tmp/.claude/memory/atlas"

cp "$ROOT/.claude/hooks/session-start-context.sh" "$tmp/.claude/hooks/"

# ── Stub the scripts the hook calls, each recording one line per invocation ──
mkstub() { # name
  cat > "$tmp/.claude/scripts/$1" <<EOF
#!/usr/bin/env bash
echo "\$(basename "\$0") \$*" >> "$tmp/calls.log"
EOF
  chmod +x "$tmp/.claude/scripts/$1"
}
for s in regen-skill-registry.sh initiative-state.sh memory-index.sh \
         memory-recall.sh atlas-refresh.sh; do mkstub "$s"; done

# Atlas manifest that is STALE (old date + different sha) so the atlas branch fires.
cat > "$tmp/.claude/memory/atlas/manifest.json" <<'EOF'
{"updated_at":"2020-01-01T00:00:00+00:00","git_sha":"deadbeef",
 "frameworks":{"web":"unknown","api":"unknown","orm":"unknown"}}
EOF

run_boot() { ( cd "$tmp" && bash .claude/hooks/session-start-context.sh </dev/null >/dev/null 2>&1 ); }

# ── First boot: heal runs INLINE (sync + rebuild), atlas BACKGROUNDS ─────────
: > "$tmp/calls.log"
t0=$(date +%s); run_boot; t1=$(date +%s)
grep -q 'initiative-state.sh sync'  "$tmp/calls.log"; check "first boot runs initiative-state.sh sync inline" $?
grep -q 'memory-index.sh rebuild'   "$tmp/calls.log"; check "first boot runs memory-index.sh rebuild inline" $?
sleep 0.3   # let the backgrounded atlas stub write
grep -q 'atlas-refresh.sh'          "$tmp/calls.log"; check "first boot backgrounds atlas-refresh (stale)" $?
[ $((t1 - t0)) -le 2 ]; check "first boot completes in <=2s (stubs; budget check)" $?

# Markers created → gate the day.
[ -f "$tmp/.claude/memory/.cache/boot-heal-$(date +%Y%m%d)" ]
check "boot-heal marker created (dated)" $?
[ -f "$tmp/.claude/memory/.cache/boot-atlas-$(date +%Y%m%d)" ]
check "boot-atlas marker created (dated)" $?

# ── Second boot same day: gated — sync/rebuild/atlas do NOT re-run ───────────
: > "$tmp/calls.log"
run_boot
sleep 0.3
! grep -q 'initiative-state.sh sync' "$tmp/calls.log"; check "second boot same day does NOT re-sync (gated)" $?
! grep -q 'memory-index.sh rebuild'  "$tmp/calls.log"; check "second boot same day does NOT re-rebuild (gated)" $?
! grep -q 'atlas-refresh.sh'         "$tmp/calls.log"; check "second boot same day does NOT re-refresh atlas (gated)" $?

echo "passed: $pass"
echo "failed: $fail"
[ "$fail" -eq 0 ]
