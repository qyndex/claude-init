# T-322 — bounded protected source/run/log observer

Actual RED at 13:52:43 Sydney on 2026-10-16 failed the missing observer before
source implementation. The first implementation passed 30 offline cases. A
supplemental actual RED then exposed acceptance of unprefixed bare JSON; selected
result lines now require the server log timestamp format. This is a formatting
constraint, not cryptographic provenance. The canonical GREEN was refreshed at
13:55:18 with 35 cases. The original RED and supplemental prefix failure remain.

The tests create a real disposable Git checkout with explicitly synthetic source
files, mock fixed read-only GitHub responses and use a real local fake-gh child
for subprocess bounds. They prove current-main/clean-checkout SHA identity,
exact successful same-repository workflow/run/attempt/job/step validation,
nonoverlapping completed windows and exact expected drill [1,0], recovery [1],
repeat [0] safe results. They reject changed/foreign/failed/boolean identities,
source drift, dirty source, unsupported timestamp precision, duplicate/extra
results, ambiguous jobs and byte/call exhaustion. GitHub's seven-fraction log
prefix format is accepted; run metadata preserves supported microsecond precision.
Shell source echoes that are not standalone result lines are not selected.

Actual fake-gh tests assert fixed `--hostname github.com --method GET` arguments
and omission of Slack/state-writer credentials from its environment. Canonical
encoded slash branches remain allowed. Actual streamed output above 2 MiB must
fail specifically at the existing bounded-process output limit; successful reads
exhaust the 32 MiB total budget, and call 129 is refused. Duplicate JSON is
rejected before it can act as API metadata. No live network or Slack calls occur.

The sandbox initially prevented the existing bounded subprocess cleanup guard
from inspecting `/bin/ps`, yielding `process cleanup status uncertain`; that exact
failed GREEN is retained as sandbox-cleanup-failure.log. The guard and precise
output-limit assertion were not weakened. The actual final suite passed with
process inspection enabled, and the parent independently repeated all 35 cases.

Local acceptance is `bash .claude/scripts/test/factory-reporting-queue-evidence-source.sh`.
A live invocation later requires a fresh clean reviewed checkout matching the
actual current default-branch SHA. Git-status-visible tracked/untracked source entries under
.claude/scripts and the queue workflow path must be clean; normal Git ignore
rules still apply. Use a fresh isolated checkout for live verification; no
caller-supplied dirty-source bypass is offered. Observation responses retain only IDs, source SHA, windows, counts
and log hashes; raw job logs are never written by the observer. Existing
GitHub authorization must read these endpoints, otherwise it fails closed.

This helper has no live CLI, journal/publication proof or rollout credit yet.
Those remain T323/T324 and T318. Its output is administrative run observation,
not a native attestation or independent local Slack receipt verification. The
parent's pre-existing uncommitted disabled-workflow clarification is preserved
and excluded from this implementation commit.
