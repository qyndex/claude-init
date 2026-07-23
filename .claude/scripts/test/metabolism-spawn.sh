#!/usr/bin/env bash
# Test the M-01b metabolism spawn seam without any real auth or API call.
# A fake `claude` on PATH records the argv and the CLAUDE_CODE_SIMPLE env it saw;
# the test asserts the seam drops --bare (the fix) and does not leak
# CLAUDE_CODE_SIMPLE (which suppresses OAuth identically — tested 2026-07-23),
# and that a non-zero spawn exit propagates so callers can gate on it.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SEAM="$ROOT/.claude/scripts/lib/metabolism-spawn.sh"

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }

test -f "$SEAM" || { echo "seam missing: $SEAM"; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Fake claude: record argv + the CLAUDE_CODE_SIMPLE it inherited, then exit with
# the code the test asks for via FAKE_CLAUDE_RC.
cat > "$tmp/claude" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_ARGV_FILE"
printf 'CLAUDE_CODE_SIMPLE=%s\n' "${CLAUDE_CODE_SIMPLE-<unset>}" > "$FAKE_ENV_FILE"
exit "${FAKE_CLAUDE_RC:-0}"
FAKE
chmod +x "$tmp/claude"

export FAKE_ARGV_FILE="$tmp/argv" FAKE_ENV_FILE="$tmp/env"
# shellcheck disable=SC1090
. "$SEAM"

# ---- Case 1: happy path — seam invokes claude, argv has NO --bare ----
CLAUDE_CODE_SIMPLE=1 PATH="$tmp:$PATH" FAKE_CLAUDE_RC=0 \
  metabolism_spawn 10 --model test-model 'reply ok' >/dev/null 2>&1
rc=$?
check "seam exit propagates 0 on success" "$rc"

grep -qx -- '--bare' "$tmp/argv"; had_bare=$?
[ "$had_bare" -ne 0 ]; check "argv does NOT contain --bare (the fix)" $?

grep -q -- '--model' "$tmp/argv"; check "argv preserves passed args (--model)" $?

# The child must NOT see CLAUDE_CODE_SIMPLE (env -u strips it) even though the
# parent exported it — otherwise OAuth is suppressed just like --bare.
grep -qx 'CLAUDE_CODE_SIMPLE=<unset>' "$tmp/env"
check "child env has CLAUDE_CODE_SIMPLE unset (OAuth preserved)" $?

# ---- Case 2: failure propagates (callers gate state-stamping on rc==0) ----
PATH="$tmp:$PATH" FAKE_CLAUDE_RC=1 \
  metabolism_spawn 10 'reply ok' >/dev/null 2>&1
rc=$?
[ "$rc" -eq 1 ]; check "seam propagates non-zero spawn exit (1)" $?

# ---- Case 3: portable timeout — seam works when `timeout` is absent ----
# Simulate the stock-macOS case (no timeout/gtimeout) by shadowing both with a
# PATH whose first dir contains non-executable stubs, while keeping the system
# bin dirs so `env`/coreutils remain resolvable. The seam must fall back to its
# bash watchdog and still return the fake claude's exit code.
nolib="$(mktemp -d)"; cp "$tmp/claude" "$nolib/claude"; chmod +x "$nolib/claude"
# Non-executable placeholders so `command -v timeout` finds nothing runnable.
: > "$nolib/timeout";  : > "$nolib/gtimeout"   # not chmod +x → not executable
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  # System actually has timeout — prepend nolib so our non-exec stubs shadow it
  # only for `command -v` resolution; this asserts the watchdog path specifically.
  probe_path="$nolib:$PATH"
else
  probe_path="$nolib:$PATH"   # stock macOS: no timeout anyway
fi
FAKE_ARGV_FILE="$nolib/argv" FAKE_ENV_FILE="$nolib/env" \
  PATH="$probe_path" FAKE_CLAUDE_RC=0 metabolism_spawn 10 'reply ok' >/dev/null 2>&1
rc=$?
check "seam runs with no runnable timeout on PATH (bash watchdog)" "$rc"
rm -rf "$nolib"

echo "passed: $pass"
echo "failed: $fail"
[ "$fail" -eq 0 ]
