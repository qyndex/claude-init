#!/usr/bin/env bash
# Generated protected settings supply fixed absolute pinned paths and event.
set -euo pipefail
[ "$#" -eq 3 ] || [ "$#" -eq 4 ] || exit 2
for path in "$1" "$2" "$3"; do case "$path" in /*) ;; *) exit 2 ;; esac; done
event="${4:-PostToolUse}"
case "$event" in PostToolUse|PostToolUseFailure) ;; *) exit 2 ;; esac
exec "$1" -I -S "$2" --descriptor "$3" --event "$event"
