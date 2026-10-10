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

## Slack runner (spec 016)

Copy `factory/digest.example.json` into a protected configuration location outside implementation worktrees. Supply repository, target branch, Slack team ID, channel ID, initial UTC timestamp and absolute database path. Keep `enabled: false` until identity and delivery have been tested. Bot credentials belong in the runner's protected environment as `FACTORY_SLACK_BOT_TOKEN`; never store them in JSON, repository files or chat. The bot needs `chat:write` and channel history access (`channels:history` for public channels or `groups:history` for private channels), and must join the target channel.

Run `python3 .claude/scripts/factory-slack-digest.py --config /absolute/path/to/protected-digest.json` periodically from a trusted local scheduler. Each invocation chooses the most recent due 08:00 Australia/Sydney cutoff, so DST does not require changing a UTC cron expression. Existing pending reports finish before later catch-up reports. Credentials and trusted state must remain available to the scheduler; this spec installs no scheduler and does not add Slack account defaults.

The transport verifies workspace/bot identity using `auth.test`, posts escaped plain text with key/hash metadata using `chat.postMessage`, and reconciles bot-owned messages using cursor-paginated `conversations.history`. These contracts follow [Slack message posting](https://docs.slack.dev/reference/methods/chat.postMessage/), [history](https://docs.slack.dev/reference/methods/conversations.history/) and [identity](https://docs.slack.dev/reference/methods/auth.test/). HTTP redirects are refused to avoid forwarding authorization; API failures are redacted and never become a PASS. Single-message text is capped at 35,000 characters; larger reports block and need a verified attachment adapter rather than omitting merges. Every merge retains its PR/merge identity; authentic receipts add task/spec and producer-run references. Titles are bounded and do not become mentions or formatting commands.

A missing message in history is not proof that no message was sent. Unknown, expired, rate-limited, deleted or inaccessible history leaves the batch uncertain and surfaces a blocker; it never triggers an automatic resend. Exact text/metadata and the authenticated bot sender must match. Duplicate reports or server-mutated content block confirmation. A live account must demonstrate the actual response/metadata contract before enabling its schedule. Reports contain non-sensitive identifiers only in metadata; message content remains visible under the channel's access policy.

`--status-only` opens existing SQLite state read-only and exits 1 when the latest due interval remains undelivered after the configured grace (default 60 minutes). Uninitialized, disabled or missing state is a blocker. This is a watchdog signal for a scheduler/monitor, not an independent notification delivery path. The watchdog itself has no Slack credential requirement.
