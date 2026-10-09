#!/usr/bin/env bash
# Regression: installed subagent hook recalls task-scoped context.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "jq required"; exit 0; }

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.claude/hooks" "$tmp/.claude/scripts" "$tmp/specs/active" \
         "$tmp/plans/active" "$tmp/tasks" "$tmp/.swarms/coordinator"
cp "$ROOT/.claude/hooks/subagent-context.sh" "$tmp/.claude/hooks/"

# Recording stub: capture the --paths value memory-recall.sh is called with.
cat > "$tmp/.claude/scripts/memory-recall.sh" <<EOF
#!/usr/bin/env bash
while [ \$# -gt 0 ]; do
  case "\$1" in
    --paths) echo "\$2" >> "$tmp/recall-paths.log"; shift 2 ;;
    *) shift ;;
  esac
done
EOF
chmod +x "$tmp/.claude/scripts/memory-recall.sh"

# Fixture: one active spec/plan + an in-progress task carrying `files:` code paths.
: > "$tmp/specs/active/010-x.md"
: > "$tmp/plans/active/010-x.md"
printf '{"phase":"implementing","spec":"specs/active/010-x.md","plan":"plans/active/010-x.md"}' \
  > "$tmp/.swarms/coordinator/workflow-state.json"
cat > "$tmp/tasks/TASKS.md" <<'EOF'
# TASKS
- [~] T-500 | spec:010 | files: .claude/scripts/target-a.sh, src/api/handler.py | accept: true
EOF

( cd "$tmp" && printf '{"tool_name":"Agent","tool_input":{"subagent_type":"implementer"}}' \
  | bash .claude/hooks/subagent-context.sh >/dev/null 2>&1 )

paths_seen=$(cat "$tmp/recall-paths.log")

# The task's code paths must have reached recall.
printf '%s' "$paths_seen" | grep -q 'target-a\.sh'
check "recall scoped to the in-progress task's .sh code path" $?
printf '%s' "$paths_seen" | grep -q 'handler\.py'
check "recall scoped to the task's second code path" $?
# The spec is still in scope (M-15 adds task code, doesn't replace spec/plan).
printf '%s' "$paths_seen" | grep -q '010-x'
check "spec/plan still in recall scope (task code is ADDED, not substituted)" $?

echo "passed: $pass"
echo "failed: $fail"
[ "$fail" -eq 0 ]
