# Deploy Integration — Bring Your Own (BYO)

> The harness does **not** ship a working deploy pipeline. `.github/workflows/canary-deploy.yml` is a **STUB**: its steps echo placeholders and `sleep`. Deploy is Bring-Your-Own — this document is the checklist for wiring your platform into the stub.

## Why a stub, not a real pipeline

`claude-init` is a stack- and platform-agnostic template harness. A real deploy pipeline is inherently project-specific: it depends on your target platform (Kubernetes + Argo Rollouts, Flagger, AWS CodeDeploy, Vercel, Fly.io, Render, bare metal, …), your secret store, your traffic-shifting mechanism, and your rollback contract. Shipping a concrete pipeline would either be wrong for most consumers or silently no-op in a way that hides un-deployed changes.

Instead the harness ships:

- a **stub** `canary-deploy.yml` with the progressive-rollout _shape_ (1% → 10% → 50% → 100%, with an SLO-burn watch between ramps), and
- this checklist for replacing the stub steps with real platform calls.

The stub preserves the rollout _discipline_ (progressive ramp, SLO-burn gate, auto-rollback decision point) so consumers adopt the pattern rather than reinventing it.

## What the stub already gives you

`canary-deploy.yml` has the skeleton wired:

| Step                  | Stub behavior                         | What you replace it with                                  |
| --------------------- | ------------------------------------- | --------------------------------------------------------- |
| Parse SLO for service | reads `slo.yml` tier + rollback flags | keep as-is (already real)                                 |
| Canary at 1%          | `echo` + `sleep 600`                  | your traffic-shift command (e.g. Argo Rollouts promote)   |
| Watch SLO burn        | real Prometheus burn-rate query       | point `PROM_URL` / `CANARY_SERVICE` at your observability |
| Promote to 10%        | `echo` + `sleep 1800`                 | your traffic-shift command                                |
| Promote to 50% → 100% | `echo`                                | your final-ramp command                                   |

The SLO-burn watch is **already real** (Round 12 A): it queries `$PROM_URL` and auto-rollback-fails on a 14.4× fast-burn breach. You only need to set the repo variables `PROM_URL` and `CANARY_SERVICE`.

## Adoption checklist

Work through these in order. Each item is a gate — do not advance until the prior item is green.

### 1. Secret + variable map

- [ ] Identify the secrets your deploy needs (registry creds, cloud provider keys, kubeconfig, platform API token).
- [ ] Store them in **GitHub Actions secrets** (repo or environment scope), never in the workflow file.
- [ ] Set the repo variables the stub reads: `PROM_URL` (Prometheus base URL), `CANARY_SERVICE` (metric label value).
- [ ] Confirm no secret is interpolated into a `run:` block via `${{ }}` — use `env:` with quoting (see the workflow-injection guide linked below).

### 2. Target platform

Pick one and replace the `# Provider-specific:` placeholder lines:

- [ ] **Kubernetes + Argo Rollouts**: `kubectl argo rollouts set image …` then `… promote --percentage=N`.
- [ ] **Flagger**: annotate the canary resource; Flagger drives the ramp from its own analysis.
- [ ] **AWS CodeDeploy**: `aws deploy create-deployment` with a `CodeDeployDefault.Canary10Percent5Minutes` config.
- [ ] **Vercel / Fly / Render**: call the platform CLI/API; most have native canary or alias-swap primitives.
- [ ] **Other**: implement the four ramp steps with whatever traffic-shifting primitive your platform exposes.

### 3. Promotion gates

- [ ] Confirm `slo.yml` has an entry for each service you deploy (tier + `auto_rollback`).
- [ ] Decide the soak time between ramps (the stub uses 10 min at 1%, 30 min at 10%). Tune to your traffic volume — low-traffic services need longer soaks to accumulate signal.
- [ ] Wire the SLO-burn watch to gate **every** ramp, not just the 1% step (the stub only watches after 1%; add the watch step between 10%→50% and 50%→100% for T1 services).

### 4. Rollback contract

- [ ] Define what "rollback" means on your platform (Argo `undo`, CodeDeploy `stop-deployment --auto-rollback-enabled`, alias swap back, …).
- [ ] Wire it to the `::error::SLO burn breach` exit path so a burn breach auto-rolls-back instead of just failing the job.
- [ ] Confirm rollback is idempotent and safe to run when no canary is in flight.

### 5. Verification before first real deploy

- [ ] Run the workflow in a staging environment first (`workflow_dispatch` with a staging service).
- [ ] Confirm the SLO-burn watch can actually reach `$PROM_URL` from the runner (network/firewall).
- [ ] Confirm a deliberately-bad canary triggers the rollback path (chaos test).
- [ ] Only then enable for a T1 production service.

## Relationship to the rest of the harness

- **`merge-gate.yml`** gates _merge to main_ (tests, security, evidence). `canary-deploy.yml` gates _production rollout_. They are independent — a green merge gate does not deploy anything.
- **`slo.yml`** is the single source of per-service tier and auto-rollback policy. Both this workflow and the SLO-burn alerting read it.
- **`docs/PLAYBOOK.md`** has the operational runbook (incident response, rollback drills).

## Out of scope for this harness

- Multi-environment promotion (staging → prod gating) — that is a separate spec (008) when a real consumer needs it.
- Blue/green vs canary strategy selection — pick per service; the stub assumes canary.
- Database migration coordination during deploy — platform- and ORM-specific; document it in your project, not here.

## References

- Workflow injection hardening: https://github.blog/security/vulnerability-research/how-to-catch-github-actions-workflow-injections-before-attackers-do/
- Argo Rollouts: https://argo-rollouts.readthedocs.io/
- Flagger: https://flagger.app/
- AWS CodeDeploy canary configs: https://docs.aws.amazon.com/codedeploy/latest/userguide/deployment-configurations.html
- Spec 002 AC-8 (this document's originating acceptance criterion): `specs/active/002-audit-remediation.md`
