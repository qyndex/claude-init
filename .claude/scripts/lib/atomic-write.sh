#!/usr/bin/env bash
# Atomic-write library (Spec 001 AC-22).
#
# Sourced — not executed (exempt from the executable-bit requirement; validate.sh
# skips lib/*). Provides one primitive used by every state writer in the harness
# so a crashed/interrupted write can never leave a half-written JSON state file.
#
#   write_atomic <target> [<content>]
#
# Content source:
#   - if <content> is given, that string is written (a trailing newline is added);
#   - otherwise content is read from stdin verbatim.
#
# Mechanics:
#   - the temp file is created with mktemp IN THE SAME DIRECTORY as the target,
#     so the final mv is a same-filesystem rename (atomic), never a cross-device
#     copy that could be observed half-done;
#   - mv -n (no-clobber) is used: if the target already exists the write does NOT
#     overwrite it. This makes write_atomic a create-or-fail primitive.
#
# Return codes:
#   0  wrote the target successfully
#   1  target already existed — mv -n refused to clobber (temp is cleaned up)
#   2  usage error (no target given) or the temp write itself failed
#
# Callers that intend to REPLACE an existing file write to a fresh temp name and
# rename, or remove the target first; the no-clobber default is deliberate so an
# accidental double-write surfaces rather than silently overwriting.

write_atomic() {
  local target="${1:-}" dir tmp
  if [ -z "$target" ]; then
    return 2
  fi
  dir="$(dirname "$target")"
  mkdir -p "$dir"
  # Same-directory temp → the mv below is an atomic rename, not a copy.
  tmp="$(mktemp "$dir/.$(basename "$target").XXXXXX")" || return 2

  if [ "$#" -ge 2 ]; then
    printf '%s\n' "$2" > "$tmp" || { rm -f "$tmp"; return 2; }
  else
    cat > "$tmp" || { rm -f "$tmp"; return 2; }
  fi

  # No-clobber: refuse to overwrite an existing target. mv -n exits 0 even when
  # it declines the move, so detect a surviving temp + existing target as the
  # collision signal and report it as return 1.
  if [ -e "$target" ]; then
    rm -f "$tmp"
    return 1
  fi
  mv -n "$tmp" "$target"
  if [ -e "$tmp" ]; then
    # mv -n declined (target appeared between the check and the mv — a race).
    rm -f "$tmp"
    return 1
  fi
  return 0
}

# replace_atomic <target> [<content>]
#
# Atomic in-place REPLACE for state files that are rewritten every run (fleet
# state, manifests, evidence bundles, per-turn heartbeats). Same same-dir mktemp
# + rename guarantee as write_atomic, but uses `mv -f` so an existing target is
# overwritten in a single atomic step — a reader never sees a half-written file,
# and the new content always lands. Use this (not write_atomic) wherever the
# previous code did a plain `> target.json` redirect.
#
# Return codes:
#   0  replaced the target successfully
#   2  usage error (no target) or the temp write itself failed
replace_atomic() {
  local target="${1:-}" dir tmp
  if [ -z "$target" ]; then
    return 2
  fi
  dir="$(dirname "$target")"
  mkdir -p "$dir"
  tmp="$(mktemp "$dir/.$(basename "$target").XXXXXX")" || return 2

  if [ "$#" -ge 2 ]; then
    printf '%s\n' "$2" > "$tmp" || { rm -f "$tmp"; return 2; }
  else
    cat > "$tmp" || { rm -f "$tmp"; return 2; }
  fi

  mv -f "$tmp" "$target" || { rm -f "$tmp"; return 2; }
  return 0
}
