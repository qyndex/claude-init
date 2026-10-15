---
id: 050
slug: request-intake-router
status: shipped
owner: "@codex"
human_owner: "@operator" # adopting repository supplies the actual accountable owner
created: 2026-10-12
updated: 2026-10-16
complexity: L
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Spec 050: Automatic request intake and Scout routing

## Problem statement

The factory has a governed execution path for approved specifications, plans and tasks, but no complete intake contract that connects ordinary requests to that path. Claude Code prompt hooks currently provide context and keyword skill hints; existing Slack intake accepts explicit authenticated factory feedback/hotfix commands. Users therefore have to identify the workflow themselves, while a request such as “add login” or “continue” has no maintained, stateful Scout-first decision contract. This feature makes supported requests enter the appropriate permitted workflow while preserving independent approval and execution controls.

Source: the user's current request to address the automatic Scout-first intake gap, recorded in this task context on 2026-10-12. The human approved spec050 in this task on 2026-10-12. The user confirmed all four recommended scope decisions in this task on 2026-10-12. Approval authorizes the technical plan and scoped implementation; existing live activation and protected authority decisions remain separate.

## Goals

In scope:
- A structured, durable intake decision for every request on explicitly supported, enabled entry points.
- Initial entry coverage for installed Claude Code prompt intake and the existing authenticated Slack feedback command bridge.
- Lightweight intake on every supported prompt; read-only Scout assessment for change requests and uncertain cases.
- Stateful continuation that resolves existing approved work, clarification answers and changed requirements.
- Automatic initiation of permitted answers, inspection, proposal drafting and eligible continuation, with human approval for new or materially changed scope.
- Deterministic enforcement of intake prerequisites at factory action boundaries, independently of model recommendations.

## Non-goals

Explicitly out of scope:
- Generic Slack conversation ingestion, GitHub issue/comment intake, Codex or other IDE coverage without a separately approved adapter.
- Implementation of this spec before its approval; new cloud workers, reviewer wakeups, authority activation, merges, deployments or weakened release gates.
- Treating prompt hints, routing records, Scout judgments or editable installed hooks as privileged eligibility proof.
- Replacing existing approval, verification, receipt, legacy characterization or private storage contracts.
- Selecting a new routing model, provider, external monitoring vendor or pricing policy.

## User stories

- As a requester I want ordinary language to enter the appropriate workflow so that I do not have to know factory command names.
- As a requester I want follow-up requests to retain their work context so that “continue” resumes the intended approved task and clarification answers update the same proposal.
- As an accountable owner I want new or changed requirements surfaced as proposed scope so that automation cannot approve its own work.
- As an adopter I want explicit runtime coverage and prerequisites so that installing a hook does not imply universal routing or production authority.
- As an operator I want failed and replayed intake to have explicit recorded outcomes so that recovery cannot duplicate work or silently bypass a decision.

## Acceptance criteria

1. **AC-1** — Supported entry coverage: Every submitted request in each enabled, supported Claude Code entry fixture and every eligible existing Slack feedback command produces one observable intake outcome before the factory initiates a dependent action. A maintained coverage inventory names the tested runtime/version, installation prerequisites, enabled entry points and unsupported surfaces. Missing or disabled prerequisites are reported as unsupported or blocked; no universal interception claim is made. Internal agent/subagent messages and bridge output do not recursively re-enter human intake.
2. **AC-2** — Bound request identity: An intake record binds source and source revision, authenticated actor where available, repository, relevant ref/content revision, conversation/request identity and parent continuation. Exact delivery retries under the same submission key return the recorded outcome without duplicate Scout assessment or workflow start. Distinct human submissions of identical text, including two separate “continue” messages, retain distinct submission identities; text hashing alone is insufficient. Where an entry lacks a stable turn identifier, its documented identity contract must distinguish new submissions from retries or block ambiguous replay. Edits are linked new revisions, not silent overwrites. Conflicting duplicate payloads, foreign repositories, edited sources and actor/ref mismatches cannot reuse an incompatible decision.
3. **AC-3** — Explicit disposition: Every completed decision states its rationale, evidence references, uncertainty, applicable approved spec/plan/task references or their absence, and permitted next action. Outcomes distinguish answer, status/inspection, existing approved work, new feature/changed requirement, behavior defect, clarification required, risk/control request, unsupported source and blocked intake. Requests containing several intents preserve each intent and cannot hide new scope inside an approved continuation.
4. **AC-4** — Stateful continuation: “Continue” resolves to the single eligible bound work item or asks a targeted question if none or several qualify. Clarification replies update the existing proposal; status questions do not create specifications. An added requirement invalidates affected decisions and becomes proposed scope. Unrelated prompts remain separate requests; one spec per message is not the default.
5. **AC-5** — Read-only Scout: Scout may inspect trusted context and report observations, affected scope, existing contract matches and missing information. Scout cannot modify candidate implementation or authoritative policy, execute candidate code, approve a spec, issue an execution credential, merge or deploy. Context access is bounded to permitted request/repository material; controller/reviewer credentials and unrelated private feedback state are inaccessible. Attempts to request those capabilities fail with no effect. Draft writing is a separately permitted workflow after a validated disposition.
6. **AC-6** — Enforced prerequisites: The deterministic factory controller validates the decision schema, source bindings, current evidence and existing authoritative eligibility before each governed action enumerated in the coverage inventory, including proposal publication, task enqueue/start and implementation mutation. Ordinary filesystem or IDE edits outside these controlled paths are not claimed to be universally intercepted. Each path claimed as mandatory integrates actual dispatch and mutation guards; additional keyword hints or prompt instructions alone do not satisfy this criterion. Implementation mutation cannot proceed with missing, malformed, stale or ambiguous intake, or without a current approved specification that authorizes that mutation under existing rules. Draft proposal writing may proceed under a validated draft disposition and cannot promote itself to approved scope. A valid routing record alone grants no authority. A bypassed or edited local hook cannot manufacture protected eligibility; any runtime whose interception cannot be enforced is documented as advisory and cannot claim guaranteed gated execution.
7. **AC-7** — Scope and approval: A new feature or material change enters clarification and a proposed specification, then requires human approval before technical planning/task execution under the existing phase contract. Existing approved work resumes automatically only when its current plan/task and all existing eligibility gates pass. Typo/document maintenance follows the applicable existing lightweight rule without self-authorizing wider behavior changes. An approval denial or unresolved open question blocks the affected implementation path.
8. **AC-8** — Defect handling: A behavior bug is matched to the existing approved contract or becomes proposed repair scope when no match is established. Evidence collection and reproduction use the existing approved isolation and execution boundaries; Scout does not run candidate code on the host. Uncharacterized legacy paths remain fenced until their existing characterization prerequisite is satisfied. “Hotfix” does not bypass approval or delivery controls.
9. **AC-9** — Durable recovery and privacy: Durable intake state records decision revisions, permitted transitions and action-start identities before dependent effects. Restart, retry and concurrent delivery cannot start the same work twice; unresolved effects fence replay until reconciled. Replay identity binds request revision and permitted action identity, while competing requests targeting the same approved task/stage/revision remain serialized by existing task claims and fences. Distinct identical submissions retain separate intake records without starting duplicate task execution. Raw requests, repository excerpts and Scout output remain in the existing private storage/privacy contracts, including encrypted channels where required. Existing authorization to capture explicit Slack feedback does not authorize generic Slack capture or new public prompt telemetry; changed data flows require explicit adopter approval. Public reports contain only approved sanitized projections. Ownership, retention, source edits and incompatible state reject rather than importing unbound decisions.
10. **AC-10** — Failure contract: Timeout, quota/provider unavailability, invalid output, missing context or storage failure produces an explicit blocked/clarify outcome with zero dependent candidate mutation. There is no silent successful route or alternate model/provider fallback. A separately validated answer/read-only/question contract may continue only when it does not rely on the failed decision; the user sees what is blocked and the available next step.
11. **AC-11** — Freshness and control requests: Changed request text, material repository/ref changes, changed approved scope or revoked policy invalidates affected decisions before dependent action. Prompts such as “skip the gates” and instructions embedded in untrusted repository/GitHub content cannot change authoritative policy or become approval evidence. Stop/pause/revocation requests retain their existing precedence and do not wait for expensive Scout assessment before stopping governed work.
12. **AC-12** — Observable bounded operation: Lightweight intake does not invoke Scout for the maintained answer/status fixture set. Scout-required requests perform at most one assessment per bound revision absent an explicit bounded retry. Proposed default limits are 20,000 characters per request, 500,000 bytes of collected context, 64 KiB of assessment output and 60 seconds per assessment, with zero automatic model retries. Adopters may select stricter finite limits in protected configuration. Exceeding a limit yields AC-10 without silent truncation. Records expose sanitized disposition, next action, blocked reason and assessment count; private evidence retains precise provenance. Existing protected routing/model policy remains authoritative, with no invented model identity.
13. **AC-13** — Demonstrated routes and failures: Tests exercise actual supported entry paths, not only direct classifier calls. The maintained matrix includes “how does this work?”, status, approved “continue”, “add login”, behavior bug, typo/doc maintenance, ambiguous “fix it”, mixed existing/new scope, clarification reply, “skip gates”, hostile imported GitHub text, identical retries, edited messages, repository/ref mismatch, stale approval, provider/quota/schema failure, restart and concurrent duplicate delivery. Every case asserts disposition, action or blocked outcome, and absence of unauthorized effects. Each claimed supported entry has an end-to-end demonstration.
14. **AC-14** — Neutral adoption: Installation and upgrade distribute neutral disabled configuration and preserve adopter ownership. Enabling an entry requires explicit per-repository prerequisites and policy; missing values never inherit source pilot identity or authority. Installation performs no model/provider calls or cloud activation. The adopter demonstration proves intake coverage and blocking behavior while remaining separate from engineering-delivery certification.

## Constraints

- **Security:** Existing protected eligibility and isolation boundaries apply. Local developer-editable hooks provide workflow integration; they are not a privileged security boundary. Claims of enforcement must identify the protected action boundary and its tested prerequisites.
- **Privacy:** Reuse existing private runtime and encrypted feedback contracts; no plaintext public intake ledger or raw prompt telemetry.
- **Compatibility:** Preserve current explicit Slack command authentication, actor allowlists, source revision checks and receipt handling. Initial Claude Code coverage is limited to installed, documented hook/API capabilities; other clients require their own adapters.
- **Performance/resources:** No Scout call for the tested lightweight answer/status routes. The AC-12 limits are proposed acceptance budgets, not measured performance claims. The approved plan must fix their exact accounting, timeout and cleanup semantics before implementation acceptance.
- **Policy/model compatibility:** Existing approved role routing and provider constraints remain controlling. A Scout role/profile, if needed, is a later plan decision and cannot imply a new authorized model or fallback.
- **Operational scope:** Current pilot reviewer pause, disabled authority/producers and release controls remain effective. Drafting this feature does not resume or activate them.

## Rollout (required for non-trivial features — drives flag-rollout skill)

```yaml
flag:
  name: factory_request_intake
  type: permission
  default: false
  provider: none
  depends_on: []
  owner: "@operator" # adopting repository supplies the actual accountable owner
ramp_plan:
  - stage: offline_fixtures
    cohort: isolated_test_repositories
    exit_gate: "AC-1 through AC-14 pass; zero unauthorized effects"
  - stage: explicitly_enabled_local_adopter
    cohort: one_approved_adopter
    exit_gate: "Every enabled entry demonstrates intended route, retry and failure fencing"
  - stage: supported_entries
    cohort: explicitly_enabled_adopters
    exit_gate: "Coverage inventory and existing regression checks pass for each claimed runtime"
success_metric:
  name: supported_entry_conformance
  baseline: "No complete automatic intake contract currently maintained"
  target: "100% of maintained entry/route matrix; zero unauthorized effects"
  source: "Private fixture evidence and sanitized acceptance report"
auto_rollback_threshold:
  custom: "Any unauthorized action, unbound decision reuse or privacy leak pauses dependent mutation on the affected entry; disabling routing never permits an ungated fallback"
cleanup_after: "Retain the permission gate while opt-in entry support is maintained"
```

## SLOs (for any service-level change)

No new hosted service or availability promise is introduced. Acceptance covers locally installed intake and the existing Slack bridge, with finite per-request limits and explicit failures. Any future hosted intake service requires separately approved service SLOs. Exact operational limits and the operator/runbook contract must be recorded in the approved plan before enabling an adopter.

## Open questions

None remain for this proposed scope. The user confirmed these decisions on 2026-10-12:

- **Resolved OQ-1:** Claude Code prompts plus the existing explicit authenticated Slack feedback/hotfix bridge. Generic Slack, GitHub and other clients remain outside initial scope.
- **Resolved OQ-2:** Human approval for new/materially changed requirements; eligible tasks within the current approved scope may resume without repeated approval.
- **Resolved OQ-3:** Lightweight intake for every supported prompt; read-only Scout investigation for change requests and routing uncertainty.
- **Resolved OQ-4:** Automatically begin permitted answers, reads, proposed drafts and eligible continuation; existing approval, pause and execution gates remain controlling.

The human approved the exact specification on 2026-10-12; technical planning and scoped implementation are authorized.

## Dependencies

- Existing constitution and specification/clarification/plan/task workflow.
- Specs 006–014: verification, protected activation/proof, durable state, approved work and receipt recovery.
- Specs 030–035: authenticated controlled feedback, approved legacy feedback, encrypted checkpoints and hosted private feedback.
- Specs 036–041: worker environment boundaries, protected runtime routing, durable effects, offline containers, neutral adoption and private artifacts.
- Specs 043–049: production control and current activation/pilot safeguards are preserved; this spec does not authorize their activation.
- No external service or provider is selected by this draft.

## Out of scope (will be picked up later)

- Generic GitHub, generic Slack, Codex and other IDE adapters, each requiring explicit opt-in and separate coverage/authentication contracts.
- Rich intake UI, external monitoring infrastructure and new provider/model provisioning.

## Change history

- 2026-10-12 | @codex | draft | Proposed automatic intake contract for human review.
- 2026-10-12 | @codex | clarified | User confirmed all four recommended decisions; status review, no implementation approval.

## References

- Stakeholder source: current user request and clarification round in this task context, 2026-10-12; no external issue has been created.
- `.claude/CLAUDE.md`: constitution and approval boundaries.
- `.claude/settings.json`: installed UserPromptSubmit and PreToolUse integration.
- `.claude/hooks/skill-router.sh`: expressly documented keyword hint overlay.
- `.claude/skills/specify/SKILL.md`, `.claude/skills/clarify/SKILL.md`, `.claude/skills/autopilot/SKILL.md`: phase contracts and approved-work execution.
- `.claude/scripts/factory-slack-feedback.py`: existing explicit authenticated Slack command intake.
- Relevant local spec files listed in Dependencies; `specs/templates/spec.md`: drafting structure.

- 2026-10-12 | @codex | approved | Human explicitly approved spec050; live authority and reviewer pause remain separate.
