# Factory status and adoption readiness

Snapshot: 2026-10-21 (Australia/Sydney). Reviewed main baseline: `6859f476264b3d317eb1e5670d361a1ec8d520bb`. This documentation refresh is a candidate until its PR is merged.

The original approved implementation baseline is recorded as complete, and the source repository has a controlled merge pilot. Subsequent readiness amendments and operational acceptance remain incomplete. The harness is ready to install and evaluate in a new or existing repository. Unattended operation in that repository requires its own activation evidence; production readiness is not inherited from this pilot.

## Implementation versus rollout acceptance

The historical baseline audit of the [task ledger](../tasks/TASKS.md) recorded 173 unique entries for specs006–050, all marked done, with no open or blocked entries in that audited range. This does not close later readiness amendment tasks. This is an audit of published task state, not a claim that this documentation review reran every historical acceptance test. Across the whole ledger, 303 entries are done and 26 older entries are explicitly skipped; skipped historical work is not passing evidence.

The last four implementation tasks are closed:

| Task | Recorded result |
| --- | --- |
| T339 | Authenticated historical operational proof, published through PR120 |
| T318 | Historical queue acceptance retained and authenticated, published through PR120; not current global queue-health proof |
| T180 | Reviewed persistent authority activation, actual App capability, receipt and final protection/authority readbacks |
| T222 | Genuine independently verified conditional delivery of the approved adopter quickstart |

[T180 activation record](../verify/2026-10-18/T-180/activation-record.json) and [T222 delivery record](../verify/2026-10-18/T-222-delivery/delivery-record.json) distinguish local readiness declarations from actual hosted capability, delivery and activation. The [master plan](../plans/AI-SOFTWARE-FACTORY.md) remains the design and dated decision history; old progress entries are not current switch settings.

## Source-pilot evidence

- [PR122](https://github.com/qyndex/claude-init/pull/122) merged as `924c20b87222069a6d51ef9933772dd24f9f2891`. Its separate signed verifier and reviewer runs passed on the exact candidate, and [coordinator39091116896](https://github.com/qyndex/claude-init/actions/runs/39091116896) produced the authenticated fourteen-field delivery receipt.
- Receipt artifact12122193638 has ZIP SHA256 `03f2281810c1fda0930691668222215dfbd93bd87bae2d6a164686ff6d3d4723`. The dedicated App's successful exact-head eligibility check establishes actual Checks-write capability.
- Two subsequent runs were reconciled as unstarted skipped job placeholders, with no steps, runner allocation or artifacts. They receive no delivery credit. Persistent activation followed a separately reviewed reconciliation; the original safe-off stop remains recorded.
- [PR123](https://github.com/qyndex/claude-init/pull/123) published the completion records as `edd33825d5191f3ad82fc8c9892cebff2dc69686`. Its nine ordinary contexts passed, including the [full harness](https://github.com/qyndex/claude-init/actions/runs/39091778158), Claude code/security review and ADR. Its three factory contexts correctly blocked out-of-scope bookkeeping; the operator approved a separate maintenance window. All twelve strict protection requirements, empty bypass actors, settled protected policy observations and enabled authority were independently read back afterward.
- [PR125](https://github.com/qyndex/claude-init/pull/125) merged the authenticated prior-origin reuse repair and bounded error diagnostics as `6399f35c6de9d67a2fb9cb1506945319d69c691e`. Its full harness and ordinary Claude code/security reviews passed; the separately approved source-first maintenance restored all twelve strict checks, no bypass actors and existing narrow authority. This is not current reporting acceptance.
- [PR126](https://github.com/qyndex/claude-init/pull/126) merged the pinned tool-free OAuth ordinary review/evidence repair as `6e89cc6f3d8e368fd078f5652c928225bec10f03`. Eight ordinary required contexts passed, including the full native harness and retained exact-head Sonnet5.5 code/security reports. Four evidence/factory requirements used the separately approved maintenance exception; they are not passing acceptance. All twelve strict requirements and the previous narrow authority were restored and independently verified. Security retained two low hardening suggestions, no high/critical findings.
- A fresh read during this audit confirmed `FACTORY_AUTHORITY_ENABLED=true`. The policy registers **only Spec048 and its nine approved paths**. This is not approval for arbitrary feature, dependency, release or authority changes.

These are dated observations. Recheck current source, configuration, producer capacity and protections before another activation or delivery; documentation is not an authority token.

## What remains operationally unproven or intentionally gated

| Area | Current boundary / next evidence |
| --- | --- |
| Reporting freshness | Latest bounded observation: [digest39504809521](https://github.com/qyndex/claude-init/actions/runs/39504809521) had workflow success but actual `incomplete`, phase `review`, reason `job-deadline`, after13 invocations and682.603 seconds. That is not confirmed delivery or current cutoff. Preserve the cursor and intent; observe the next serialized continuation rather than duplicating sends. That observation grants no current-health or delivered-receipt credit; it does not authorize another manual run or protected log read. |
| Complete pilot loop | Observe the next due digest containing the genuine delivery, then authentic operator feedback and a separately approved amendment delivered through the same chain. Do not invent feedback or preapprove its scope. |
| Broader autonomy | Accumulate twenty useful consecutive eligible deliveries with complete receipts and the planned recovery/reporting evidence before expanding policy. One pilot delivery is not that sample. |
| Scout/native entry | Spec050's implementation and offline acceptance are complete. Mandatory intake needs a separately provisioned protected console/worker installation and actual native ordering/failure observations. Bare Claude/IDE paths remain advisory or unsupported; general native conversation delivery is unavailable. |
| Private adopters / online workers | Prove repository access, native provider execution, signed evidence and isolation for that installation. Offline container drills do not establish isolated online execution. |
| Optional attachments / monitoring | Oversized Slack attachments remain disabled under the existing uncertainty boundary. Healthchecks remains disabled; independent monitoring is optional. GitHub-only alerts share GitHub and Slack availability limits. |
| Production | The source pilot has no production target. Each adopter must configure and prove deployment, health/SLO and rollback adapters and separately enable releases. |

The original baseline ledger audit is complete; later implementation and rollout acceptance are not all complete. Do not describe the system as universally production-certified or the full operating loop as accepted yet.

## Five readiness workstreams

| Workstream | Completion evidence required | Current disposition |
| --- | --- | --- |
| Documentation/runtime follow-up | Actual source integration and fresh native checks, followed by genuine protected qualification. | PR124 and the native-build profile PR139 are merged. PR140 merged as `6859f47`; all twelve protections and prior narrow authority were independently verified restored. Its Spec033 operational acceptance remains pending. |
| Current reporting | Confirmed remote receipt and authenticated delivered cutoff covering the due Sydney digest; workflow success alone is insufficient. | Catch-up/continuation remains under verification. |
| Feedback cycle | Genuine allowlisted operator feedback referring to a confirmed report, reviewed scope amendment, independent verification, actual delivery and authenticated acceptance. | Await a confirmed report and actual operator decision; no synthetic feedback or self-approval. |
| Twenty-delivery expansion sample | Twenty useful consecutive eligible deliveries with complete authenticated receipts, no bypass/duplicate effects and the planned recovery/reporting proof. | Accumulate naturally under existing approved scope; one pilot delivery and maintenance merges cannot certify the sample. |
| Real greenfield/brownfield adopters | Execute the repository-specific checklist and genuine native proofs. | Greenfield: [qynise-platform](https://github.com/qyndex/qynise-platform), PR4 merged `1b200f9`, six protections restored. Brownfield: [nextjs-landing-page](https://github.com/qyndex/nextjs-landing-page), PR6 merged `8d9c634`, eleven protections restored. Both source contracts are integrated; publishing gates and all six factory enablement flags remain false. Hosted image, managed refresh, trusted review and shadow acceptance remain pending. Provider execution and production deployment remain deferred. |

These rows are acceptance boundaries, not new completed task claims. See [the adopter checklist](FACTORY-ADOPTER-SETUP.md#greenfield-and-brownfield-verification). Keep each unproved capability disabled or within its existing approved scope.

## Use it in another repository

1. Pin a reviewed harness commit and start with the [adopter quickstart](FACTORY-ADOPTER-QUICKSTART.md). Dry-run and inspect the transactional installation; preserve the target's own conventions, tasks and private state.
2. Follow [adopter setup](FACTORY-ADOPTER-SETUP.md). Supply the target's own repository identity, approved specifications, stack commands, protected App/environments, runtime pins and capability observations. The installer does not copy source-pilot authority, credentials, live workflows or backlog.
3. Choose the entry point. Ordinary Claude Code supports the interactive spec workflow. For mandatory Scout intake, provision the [guarded console](FACTORY-REQUEST-INTAKE.md) and its account registry before launch; copied editable hooks alone are insufficient.
4. Run the protected readiness checks and genuine independent verifier/reviewer and shadow sequence in [activation](FACTORY-ACTIVATION.md). Missing capabilities block enablement. Preflight declarations do not authenticate keys or prove a successful delivery.
5. Enable only the reviewed scope. Reporting/feedback use that repository's own protected state and destination; deployment remains separately gated. Read the [operator manual](OPERATOR-MANUAL.md) for daily operation.
