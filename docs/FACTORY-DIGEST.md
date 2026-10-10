# Durable delivery digest core

Spec 015 introduces a reusable reporting core alongside the legacy `daily-briefing.sh`. The legacy script still relies on its ship log and is not evidence of complete merge coverage or historical CI success. The new core does not invoke it or mutate global task completion.

Prepare an immutable JSON report using a trusted repository identity and configured destination:

```bash
python3 .claude/scripts/factory-digest.py \
  --db /absolute/path/to/trusted-runtime.sqlite \
  --repository owner/repository --destination configured-channel-id \
  --start 2026-10-01T00:00:00Z --sydney-date 2026-10-10
```

The caller supplies the Sydney report date. `--sydney-date` resolves 08:00 with the system zoneinfo database, including DST; future cutoffs are rejected. `--until` accepts an explicit timezone-bearing cutoff instead. The persistent stream is scoped to repository, destination and target branch; `--start` is used only on initial creation. A pending/uncertain report must finish before a later interval can be prepared. The CLI only prepares reports, never sends them or advances delivery state.

All closed PR pages are collected before report persistence. Merges in `(last delivered cutoff, new cutoff]` are sorted by timestamp and PR number. Equal-time batches are included in full. Exact PR/head/merge/revision matches against authenticated `delivery_receipts` plus `delivery_provenance` supply task/spec attribution. Use a trusted runtime database populated by the authenticated receipt adapter; candidate-controlled tables are not attestations. Unattested merges are shown with missing evidence. The report does not infer merge-time CI results or product acceptance. Delayed remote indexing/backdated merges are not reconciled by this first adapter and require a later coverage audit.

## Trusted transport contract

Installed trusted code may call `Digest.deliver(key, transport)`. The transport implements:

- `send(key, payload, destination)` returns `{key, payload_sha256, destination, message_id}` for the exact immutable bytes accepted remotely.
- `lookup(key)` returns a matching receipt, or exactly `{receipt: null, authoritative_absence: true}` when the provider can prove no effect occurred. Unknown results must not claim authoritative absence.

The core owns a per-stream OS lock across lookup/send/confirm and writes `uncertain` before send. A timeout/crash never triggers a blind resend. Recovery looks up the stable key; a matching remote receipt commits cursor advancement and confirmation together. Only authoritative absence permits retry. This is a fail-closed adapter contract, not a claim that every provider offers exactly-once delivery. Slack search alone does not prove absence; a live adapter must implement and verify suitable remote reconciliation before activation. Store the database and lock directory outside implementation worktrees and protect them from candidate writes.

No qyndex channel, token or webhook is an installer default. The operator selected qyndex/qyndex-alerts at 08:00 Sydney, but this spec adds no token, live transport, schedule or external send. Actual Slack adapter, missed-report watchdog, late-index reconciliation and integrated morning rollout remain F-05 work. Remote outage recovery is verified against disposable provider fixtures, including response loss after successful send, conflict rejection and independent-process duplicate exclusion.
