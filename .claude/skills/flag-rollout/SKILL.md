---
name: flag-rollout
description: Phased rollout discipline for production. Ship code default-OFF, ramp 1%→10%→50%→100% with monitoring windows, auto-rollback on metric breach, scheduled cleanup. The "phased delivery in prod" backbone.
when_to_use: A feature is merged and ready to ship to users. User says "roll it out", "ramp the flag", "go to 10%", "/flag rollout". Autopilot ships incomplete-but-acceptable work behind a flag rather than escalating.
allowed-tools: Read, Glob, Grep, Edit, Write, Bash, TodoWrite, WebFetch
model: opus
---

# Flag Rollout

Ship code **default-OFF**. Ramp through cohorts. Auto-rollback on metric breach. Clean up when stable.

## The ramp ritual

| Stage | Flag value | Wait | Exit gate |
|---|---|---|---|
| Land | default-OFF | merge | flag exists in provider, default-OFF deployed |
| Internal | staff ON | 1-2 days | zero errors, dogfooding feedback positive |
| Canary | 1% | 24-48 hours | error rate ≤ baseline + 0.1pp; p95 latency within budget |
| 10% | 10% | 48-72 hours | error rate ≤ baseline + 0.05pp; engagement metric ≥ baseline |
| 50% | 50% | 3-7 days | success metric significant (per spec's `success_metric`) |
| 100% | 100% (default-ON in config) | observation | one full week without regression |
| Cleanup | flag deleted | T+`cleanup_after` | spec marked complete; flag removed from code |

Each row's exit gate is **mechanical** — read from observability + flag provider, not from feel.

## Emergency path — hotfixes (Round 12 D)

A hotfix is corrective, not a new capability, so it **skips the gradual ramp**. When a spec carries `service_tier: emergency` (set by the hotfix pipeline):

**Pre-check — is the target flag still mid-ramp?** Before emergency-100%, query the provider for the *target* flag's current rollout %. Two cases:

- **Target is at 100% (or unflagged baseline code).** The failure is live for everyone → emergency deploy to 100% immediately. This is the normal hotfix case.
- **Target is a NEW-feature flag still mid-ramp (< 100%, e.g. the bug was found in the 10% canary).** Do **NOT** jump to 100%. Deploy the fix to the **current ramp cohort only** (match the present %), keep `auto_rollback` ON, and let the normal ramp resume once the fix is confirmed. Promoting an unvalidated feature to everyone under cover of a "hotfix" defeats the ramp's blast-radius limit — you'd be exposing the *whole* feature to 100% of users, not just fixing the bug for the cohort already seeing it.

| Stage | Flag value | Wait | Exit gate |
|---|---|---|---|
| Emergency deploy | 100% if target already at 100%, else **current ramp %** | none | fix merged + evidence bundle PASS |
| Watch | unchanged from deploy | 30-min observation | **auto_rollback STAYS ON** — `slo.yml` thresholds (error_rate ≥1%/5m, p95 ≥2x/10m) are the safety net that replaces the gradual ramp |

The gradual ramp exists to *limit blast radius of new behavior*. A hotfix's job is to *reduce* an already-live failure, so waiting at 1% would prolong the incident — but only for behavior that is *already* at that exposure. A fix for a feature still at 10% stays at 10%. The auto-rollback guardrail is what keeps emergency-100% safe: if the "fix" makes things worse, the SLO breach reverts it within minutes. When the emergency deploy succeeds, fire `repository_dispatch: flag-shipped` → the hotfix issue moves to SHIPPED (same as a normal flag at 100%).

## Process

1. **Read spec's `## Rollout` section** — flag.name, flag.type, default, success_metric, auto_rollback_threshold, cleanup_after.
2. **Verify flag exists** in the flag-provider (OpenFeature / LaunchDarkly / PostHog / Unleash). Create if missing.
3. **Check current stage** — query provider for current rollout %.
4. **Decide next action**:
   - If exit gate not met → wait
   - If exit gate met + next stage exists → ramp
   - **When the flag reaches 100% → mark the spec issue SHIPPED** (Round 11 C). Fire a repository_dispatch so `issue-lifecycle.yml` moves the board:
     ```bash
     gh api repos/:owner/:repo/dispatches -f event_type=flag-shipped \
       -F client_payload[issue_number]="$(awk '/^github_issue:/{print $2}' specs/active/<spec-id>*.md)"
     ```
   - If at 100% for ≥ cleanup_after → invoke `flag-cleanup` skill
   - If auto_rollback_threshold breached → `/rollback-flag <name>` immediately
5. **Document** the decision in `.claude/memory/playbooks/flag-rollout.md` or per-flag log.
6. **Schedule next check** (cron or scheduled-task) at the wait-window for this stage.

## Auto-rollback discipline

When ramping, the SLO burn-rate becomes the rollback trigger. Define in the spec:
```yaml
auto_rollback_threshold:
  error_rate: ">= 1% for 5 minutes"
  p95_latency_increase: ">= 2x baseline for 10 minutes"
  custom: "checkout_failure_rate >= 0.5%"
```

The release agent's post-deploy watch monitors these. If breached:
1. Flip flag to 0% (rollback-flag skill)
2. Open incident (`/incident-start`)
3. Post to Slack / page on-call
4. **Don't** revert code — flag flip is sufficient and faster

## Hard rules

- **Default-OFF unless proven otherwise.** Even for "small" changes. Costs nothing; saves everything.
- **Don't skip stages.** No "1% → 100%" leaps. Each stage is its own learning.
- **Wait the window.** Bugs surface after time, not after request count. A 24h window is a 24h window even if 1% is silent.
- **Cleanup is part of done.** A 100% flag still in the codebase is debt. Schedule cleanup at `cleanup_after`.
- **Don't ramp two related flags simultaneously.** If `db_flag` is the foundation for `api_flag`, ramp db first to 100%, then start api.

## References

- Provider-agnostic: OpenFeature spec (https://openfeature.dev/specification/)
- LaunchDarkly best practices (https://docs.launchdarkly.com/guides/best-practices)
- Pete Hodgson's "Feature Toggles" patterns (martinfowler.com)
- See also: `.claude/memory/playbooks/flag-rollout.md`, `flag-kill.md`, `flag-cleanup.md`
