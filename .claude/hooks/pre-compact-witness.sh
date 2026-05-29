#!/usr/bin/env bash
# PreCompact hook — writes a "witness brief" before compaction so nothing is silently lost.
# Pattern from mvara-ai/precompact-hook. Spawns a fresh `claude -p` subagent with empty
# context, gives it the last 50 exchanges, asks for a 6-section recovery brief.

set -uo pipefail

# Read JSON from stdin (session_id, transcript_path, etc.)
input=$(cat)
session_id=$(printf '%s' "$input" | jq -r '.session_id // "unknown"')
transcript_path=$(printf '%s' "$input" | jq -r '.transcript_path // ""')

mkdir -p .claude/memory/.cache/checkpoints
mkdir -p .claude/hooks/.log

ts=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
brief_file=".claude/memory/.cache/checkpoints/${session_id}.md"
log_file=".claude/hooks/.log/precompact.log"

echo "[$ts] PreCompact firing for session $session_id" >> "$log_file"

# ASYNC pattern: write a "brief pending" placeholder immediately so PreCompact
# completes in <1s. The witness brief fills in in the background via nohup.
# This avoids deadlock when the main session's daemon is the one being compacted
# and prevents the 55-second blocking window under load.

# Write the placeholder synchronously
cat > "$brief_file" <<HEADER
# Recovery Brief — $ts — session $session_id (pending)

(The witness subagent is generating this brief in the background. If you're
reading this immediately post-compact, the brief is still being written.
Re-read this file in 60-120 seconds for the full content.)
HEADER

# Best-effort: if transcript exists, spawn witness brief in background
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ] && command -v claude >/dev/null 2>&1; then
  witness_prompt='You are a fresh witness with an empty context window. The next message contains the last 50 exchanges from a session that was just compacted. Write a recovery brief in EXACTLY this format — 6 sections, terse:

# Recovery Brief

## 1. Who Is Here
The user identity (role / project / repo). Unclear if you cannot tell.

## 2. The Living Thread
The driving inquiry — what the user was trying to accomplish, in one sentence.

## 3. What Just Happened
Specific files modified, decisions made, last few commits. Cite paths/SHAs.

## 4. Emotional Truth
Tension or urgency. One sentence.

## 5. Key Artifacts
Files/IDs/commands the next session must know about. Bulleted list with paths.

## 6. Continue With
The single most concrete next action. Verb-first.

No preamble. Just the brief.'

  # Spawn the witness completely detached. It writes to a temp file then atomically replaces the brief.
  nohup bash -c "
    tmp=\"${brief_file}.tmp\"
    set -uo pipefail
    # JUSTIFIED: best-effort witness generation in a detached background job. A vanished transcript or timed-out/absent claude CLI yields an empty brief; the non-empty brief check below handles that without overwriting the synchronous git snapshot.
    brief=\$(tail -200 '$transcript_path' 2>/dev/null | \\
            timeout 120 claude -p --bare --append-system-prompt \"$witness_prompt\" \\
              'Write the recovery brief now based on the transcript I just gave you.' 2>/dev/null || echo '')
    if [ -n \"\$brief\" ]; then
      {
        echo '# Recovery Brief — $ts — session $session_id'
        echo
        echo \"\$brief\"
        echo
        echo '---'
        echo
        echo '## Fallback git snapshot'
        echo
        echo '### Branch'
        # JUSTIFIED: detached HEAD / non-repo falls back to the literal detached marker for the snapshot header
        git symbolic-ref --short HEAD 2>/dev/null || echo detached
        echo
        echo '### Uncommitted'
        # JUSTIFIED: snapshot is best-effort context; outside a repo git status fails and an empty section is acceptable
        git status --short 2>/dev/null || true
        echo
        echo '### Recent commits'
        # JUSTIFIED: a repo with no commits / no git makes log fail — an empty commit section is fine for a recovery hint
        git log --oneline -10 2>/dev/null || true
      } > \"\$tmp\" && mv \"\$tmp\" '$brief_file'
      echo '$(date -Iseconds) wrote brief for $session_id' >> '$log_file'
    else
      echo '$(date -Iseconds) witness subagent returned empty for $session_id' >> '$log_file'
    fi
  " > /dev/null 2>&1 &

  echo "[$ts] PreCompact spawned witness in background (pid $!)" >> "$log_file"
fi

# Always append a synchronous git snapshot to the brief — even if async witness fails,
# the post-compact context has SOMETHING immediately. The async witness overwrites
# this with the full brief when it returns.
{
  echo
  echo "---"
  echo
  echo "## Synchronous git snapshot (immediate)"
  echo
  echo "### Branch"
  # JUSTIFIED: detached HEAD / non-repo — "detached" is the intended snapshot value
  git symbolic-ref --short HEAD 2>/dev/null || echo "detached"
  echo
  echo "### Uncommitted (status)"
  # JUSTIFIED: synchronous best-effort snapshot; outside a repo git status fails and an empty section is acceptable
  git status --short 2>/dev/null || true
  echo
  echo "### Recent commits (10)"
  # JUSTIFIED: no-commit repo / no git makes log fail — empty commit section is fine for the immediate post-compact hint
  git log --oneline -10 2>/dev/null || true
  echo
  echo "### Active spec/plan"
  # JUSTIFIED: no active spec/plan yet makes the glob fail — "none" is the intended sentinel in the snapshot
  ls -t specs/active/*.md 2>/dev/null | head -1 || echo "none"
  ls -t plans/active/*.md 2>/dev/null | head -1 || echo "none"
  echo
  echo "_(Async witness brief overwrites this file with the full 6-section recovery brief in 60-120s.)_"
# JUSTIFIED: appends the snapshot to a brief file we just created in a mkdir'd dir; suppressing append errors keeps PreCompact from failing the compaction over a non-critical log write
} >> "$brief_file" 2>/dev/null

# Round 5 D2: cap the synchronous snapshot at 200 lines so a busy repo (huge git
# status, deep commit history) can't poison the next session's context with KBs
# of state. The async witness already targets ~6 short sections; this cap is the
# floor for the worst-case-no-witness scenario.
if [ -f "$brief_file" ]; then
  head -n 200 "$brief_file" > "${brief_file}.capped" && mv "${brief_file}.capped" "$brief_file"
fi

# Emit additionalContext so the post-compact context knows the brief exists
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreCompact",
    "additionalContext": "Pre-compaction witness brief saved to $brief_file. Read it post-compact if context is unclear."
  }
}
EOF

exit 0
