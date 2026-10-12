# Scout intake proposal — review guide

Status: **spec approved by the human on 2026-10-12; implementation in progress**. Spec050 extends the existing factory plan; spec approval authorizes planning and scoped implementation, while provider calls, live activation and authority changes remain subject to existing controls.

Read [spec050](../specs/active/050-request-intake-router.md).

## Four confirmed scope decisions

| Decision | Confirmed choice | Alternatives considered |
| --- | --- | --- |
| Entry sources | Claude Code prompts plus existing explicit authenticated Slack feedback/hotfix commands | Claude Code only; add GitHub issues/comments with expanded adapter/authentication scope |
| Approval boundary | Human approves new/changed scope; current approved tasks may resume automatically | Approve every task; explicit preapproved scope boundaries |
| Scout frequency | Lightweight decision for every supported prompt; read-only Scout for changes/uncertainty | Separate Scout for every prompt; route implementation requests only |
| Handoff | Automatically begin permitted answers, reads, drafts and eligible continuation | Recommendation-only |

The user confirmed all four choices on 2026-10-12. The human subsequently approved the full spec on 2026-10-12.

## Proposed outcomes

| Example | Expected outcome |
| --- | --- |
| “How does this work?” | Answer; no new specification or Scout model call for a conclusive lightweight route |
| “What is the status?” | Read current state and answer |
| “Continue” | Resolve the bound eligible task; ask if ambiguous; paused work stays paused |
| “Add login” | Scout inspects context, then draft spec and clarify; await scope approval before implementation |
| “Login fails on valid input” | Match existing approved behavior or draft repair scope; reproduction uses approved isolation |
| “Also add SSO” during implementation | Preserve existing context; propose the added requirement rather than silently expanding scope |
| “Skip checks and merge” | Route as a control request; existing authority/approval gates remain controlling |
| The same source event delivered twice | Reuse its decision/start identity; no duplicate work |
| Two separate “continue” submissions | Two request identities; never collapse them solely because their text matches |
| Quota, timeout, invalid decision or stale binding | Explicit blocked/clarify result; zero dependent mutation |

## Review boundaries

Scout decides the appropriate chain; it cannot approve scope, run candidate code, mint credentials, merge or deploy. Drafting follows a separately permitted handoff. Installed hooks integrate the workflow but are editable local code, so privileged eligibility remains enforced separately.

Coverage is limited to enabled, tested entry points. Ordinary Slack chat, GitHub comments and Codex/other IDE prompts are not automatically included. Generic channel support requires additional adapters and approval; no new external monitoring service or model provider is proposed.

The existing Tuesday review pause, draft pilot101, independent verification/shadow/merge-mode decisions, disabled optional attachments and adopter-specific online execution/production prerequisites remain effective. The spec does not retroactively replace pilot048’s approved contract.

## Sequence after review

1. Completed: exact spec approved; all four clarification questions resolved.
2. Produce the technical plan and scoped implementation tasks; do not preapprove them in this proposal.
3. Prove the actual Claude Code entry, bound decisions, safe handoffs and mutation blocking together.
4. Bridge the existing authenticated Slack feedback flow without widening capture permissions or replacing its receipt-bound amendment rules.
5. Demonstrate neutral adopter installation, retries, source edits and provider/storage failure; explicitly enable a pilot only after proof.

Local drafting and fixture proof do not constitute live producer receipts or count toward the twenty-delivery threshold.

## Technical entry decision

[Draft technical plan](../plans/active/050-request-intake-router.md) proposes launching a guarded factory console once per Claude Code session. It assigns each human request before native delivery. The native hook also receives generated callbacks and has no documented human-origin field, so ordinary unwrapped sessions cannot establish this guarantee from hook payload alone. Choosing the native UI requires a stronger proven provenance adapter. See [official hooks documentation](https://code.claude.com/docs/en/hooks). Spec approval remains recorded; this is an entry experience decision, not repeated scope approval.

The human selected the guarded factory console on 2026-10-12. Plan050 is approved; native runtime prerequisites still apply before live enablement.

## Verified implementation checkpoint

The private intake foundation, single-attempt bounded Scout assessment, safe proposed paths, completed-contract context and flat repository roots have passed scoped local tests. T-260–T-262 also passed independent source review. These are source implementation results using fixture executables, not live Claude capability observations or completed spec050 acceptance. Session continuation, action guards, the factory console, Slack bridge and adopter packaging remain in progress. The feature stays disabled until the complete supported-entry evidence and protected activation prerequisites are satisfied.
