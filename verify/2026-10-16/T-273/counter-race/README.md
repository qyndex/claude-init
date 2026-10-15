# Existing assessment fixture counter race

CI harness reported ValueError converting the assessment count while its child used truncating write_text. This fix changes only the test fixture: publish count.next via same-directory atomic replacement. Production code, authority checks and time budgets are unchanged.

The regression executes the actual counter writer extracted from the native-like fixture code under an instrumented Path.write_text. Immediately after opening its target with truncation, it reads the published counter, deterministically exposing the empty window. Old writer RED fails with the same int(empty) ValueError; atomic writer GREEN preserves the prior integer during the temporary write and publishes the next integer. The complete actual private assessment suite then passes, including concurrent duplicate-assessment fencing and exactly-one-provider-call count.

Commands: bash .claude/scripts/test/factory-intake-outcome.sh (both red and green); bash -n for changed script; git diff --check. No live model requests. Sibling audit found copies of the truncating writer, but no other fixture polling the count during an active child write. Slack and adoption concurrent scenarios wait on separate spawned markers and read counts after futures join. No sibling changes were made.
