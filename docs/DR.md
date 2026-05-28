# Disaster Recovery & Business Continuity

Round 8 F. Every multi-year factory eventually loses a region, has a backup fail silently, or finds out its restore path was never tested. This doc declares RTO/RPO targets and the drill cadence that keeps them real.

## Targets (declare per service in `slo.yml`)

| Service tier | RTO (recover-time) | RPO (recover-point) | Backup frequency | Cross-region |
|---|---|---|---|---|
| T1 (mission-critical) | 15 min | 5 min | continuous (WAL streaming) | active-active |
| T2 (important) | 4 hours | 1 hour | hourly + daily | active-passive |
| T3 (internal-only) | 24 hours | 24 hours | daily | single-region OK |

**RTO** = how long to bring the system back. **RPO** = how much data we accept losing.

## Required artifacts per T1/T2 service

1. **Backup verification** — automated daily restore of yesterday's backup to a staging DB; runs `SELECT count(*) FROM critical_table` and verifies a known fixture; fails the daily-batch if the count is impossible.
2. **Runbook** — `docs/runbooks/<service>.md` with the exact commands to:
   - Failover to standby
   - Restore from backup
   - Verify integrity post-restore
3. **Drill cadence** — quarterly DR drill per service via `/dr-drill <service>`. Failure to drill in 90 days = automatic incident.
4. **Communication plan** — who pages whom; which Slack channels; which customers get notified.

## Failure modes catalog

| Failure | Detection | Response |
|---|---|---|
| Region offline | health checks + Synthetic monitors | failover to secondary region per runbook |
| Database corruption | nightly integrity check | restore from last clean backup; replay WAL |
| Bad migration | application errors post-deploy | rollback migration; redeploy prior version |
| Encryption key loss | unable to decrypt secrets | restore from sealed-secrets backup; rotate |
| CI/CD platform outage | GitHub Actions / CircleCI down | switch to local-pr-check.sh + manual deploy via runbook |
| Cloud provider account compromise | unusual billing + access logs | emergency cred rotation; legal involvement |
| Source of truth (git) corruption | git fsck failures | restore from mirror; never push --force to disaster |

## The drill (quarterly per T1/T2 service)

`/dr-drill <service>` runs:

1. **Cordon** — mark service as "drilling" in status page (internal banner only)
2. **Snapshot** — capture current state
3. **Trigger failure** — kill primary region (or sim)
4. **Time the recovery** — wall-clock from cordon → "service responding on standby"
5. **Verify integrity** — run a known fixture's data validation
6. **Compare to RTO/RPO** — fail if RTO breached
7. **Restore primary** — failback per runbook
8. **Postmortem** — `.claude/memory/post-mortems/dr-drill-<service>-<date>.md`

## What this round adds

- `slo.yml` extended with per-service `rto:`, `rpo:`, `backup_verification:` fields
- `.claude/commands/dr-drill.md` — drill workflow
- `.claude/memory/dr-drills/` — drill history
- session-start surfaces "last drill >90d ago — schedule one" banner for any T1/T2 service

## Where this connects

- Cost of NOT drilling shows in **DORA's Time-to-Restore** (Round 8 F): high TTR = your runbook is stale
- Post-mortems from real incidents inform drill scenarios — invert the mortem to test the recovery
- Backup-verification automation is part of `daily-batch.yml` (proposed addition; not yet wired)

## Hard rules

- **Drills cannot be skipped.** A T1 service whose `last_drill` field in slo.yml is >90 days fails the `harness-doctor` gate.
- **Document the failure modes you ARE accepting.** If a service is single-region by choice, the slo.yml entry must say so explicitly. Silent single-region = a future incident waiting.
- **Restore-from-backup is the source of truth for backups.** If you've never tested restoring, you don't have backups; you have hope.
