# Spec029 queue pilot — bounded live acceptance

T318 verified the reviewed qyndex/claude-init pilot on protected source
`91839087a769bd45670df5b84cb96993bcb97d42`, merged through
[PR112](https://github.com/qyndex/claude-init/pull/112). Source T317 local
contributions and its archived first attempt remain historical and unchanged.
The actual read-only acceptance was rerun on that clean tracked source on
2026-10-16; [live-proof.json](live-proof.json) records its safe selected output and
[the task GREEN log](../../../verify/2026-10-16/T-318/green.log) retains the exact
command, real timestamp and exit0. This is verification-only characterization:
no runtime behavior was added and no RED was manufactured.

- [Drill38850566089 attempt1](https://github.com/qyndex/claude-init/actions/runs/38850566089): two fresh CLI processes in one protected job, notifications `[1,0]`.
- [Recovery38850688638 attempt1](https://github.com/qyndex/claude-init/actions/runs/38850688638): notifications `[1]`.
- [Repeat38850871872 attempt1](https://github.com/qyndex/claude-init/actions/runs/38850871872): notifications `[0]`.

The checker independently fetched bounded same-repository workflow/run/job/source
metadata, selected exact safe result lines from actual logs, read the protected
role journal, and checked each of five queue-path publications against its actual
parent/tree. Other worker report/encrypted-feedback blobs were preserved opaquely;
no raw content was decoded or persisted here. Current role bytes still matched
with no unresolved extra effects. The reviewed protected Actions jobs performed
the exact Slack bot/channel/text/metadata/receipt checks using their existing
environment credential. This local checker retrieved no Slack token and did not
independently reread Slack. The evidence is administrative correlation, not native
attestation, cryptographic attribution, exclusive-writer proof or all-history
coverage. Run log hashes are retained; raw job logs/private Slack/feedback are not.

The exact initial state revision was reviewed before first role creation, then
`FACTORY_REPORTING_QUEUE_INITIALIZE` was returned to `false`. Selected nonsecret
[pilot configuration](pilot-configuration.json), [bootstrap approval](approved-bootstrap.json),
[drill](drill-observation.json), [recovery](recovery-observation.json),
[maintenance record](maintenance-completed.md) and bounded
[main-policy observation](main-policy-observation.json) are included. The maintenance
record describes the earlier source rollout; its scratch capture references are
historical, while this package provides the durable selected observations. Factory
authority and merge mode remained off; the twelve-check policy was restored.
This documentary closeout performed no settings changes, extra Slack sends,
workflow dispatch or source push.

The labelled synthetic drill establishes actual separate workflow execution,
Slack reconciliation, fresh-process suppression, recovery and unchanged repeat.
It does not establish a real stalled worker or its concurrency/deployment cause;
old-waiting-worker detection remains covered by metadata/configuration fixtures.
AC8's actual pilot portion is now verified for this source/configuration only.
Every adopter must perform its own reviewed initialization and live acceptance.
The isolated one-pair/ordered-window,24-commit,1024-tree-entry and aggregate API/
byte bounds remain explicit capacity refusals. Shared-environment blockage,
GitHub-wide/Slack-wide outages and delayed schedules remain limitations, not SLAs.
Healthchecks remains disabled and independent monitoring remains optional.
