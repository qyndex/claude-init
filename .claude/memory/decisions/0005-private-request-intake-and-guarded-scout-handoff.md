---
name: 0005-private-request-intake-and-guarded-scout-handoff
description: "ADR-0005: Private intake and guarded Scout handoff"
metadata:
  type: decision
  status: accepted
status: accepted
spec: 050
owner: architect
subsystem: request-intake
created: 2026-10-12
---

# Private intake records with guarded factory actions and tool-free Scout

## Context

Approved spec050 requires automatic intake on installed Claude Code prompts and existing authenticated Slack feedback, preserving approval and independent execution controls. Current skill-router hooks only add hints. Factory ledger/routing already validates approved policy and owns task claims; feedback already uses private SQLite and encrypted checkpoints. Native Claude hook delivery does not establish a stable turn identifier. ADR 0005 was allocated with adr-new; the human selected the guarded factory console on 2026-10-12.

## Decision

Keep routing as untrusted assessment. A deterministic private controller records bindings and validates prerequisites at enumerated action boundaries; existing approval, scope, isolation, claims and receipt controls remain independently necessary. Tool-free Scout uses exactly the pinned protected primary planning runtime in a private clean assessment directory with a dedicated planning credential, bounded supplied context, finite aggregate output/time and no automatic retry/fallback. The model cannot mint action credentials or approval evidence.

Use additive intake-prefixed SQLite tables in existing private storage and encrypted feedback checkpoints. Record action intent before effect, reconcile lost outcomes by exact action/task fence, and leave unknown effects fenced. Assign a new per-session sequence to each human console submission through the trusted factory launcher; native hooks consume one already bound pending session/digest record rather than infer human origin. Bare native sessions are advisory. Require synchronous fail-closed hooks and observed native>=2.1.295; only an issued trusted delivery token denotes retry. Distinct identical prompts remain distinct intake records, while existing task claims prevent duplicate execution. Slack keys remain authenticated message/edit identities after current receipt validation. Internal agent and bridge output never enter human ingress.

Default is disabled and neutral. Once a protected entry is enabled, failure or disablement pauses dependent mutation rather than falling through ungated. Editable hooks integrate local workflow but are not a privileged security boundary. Unknown Bash cannot be certified safe by ad hoc parsing; controlled hook sessions permit explicit read operations or eligible bound task execution. Uncovered editor/MCP/raw-shell paths remain advisory and documented. Native tool-disable/config-isolation capabilities must be observed before enablement; no fictional runtime API is assumed.

## Alternatives

- Keyword hints/prompt-only instructions: insufficient for actual dispatch and mutation prerequisites.
- Scout on every prompt: adds unnecessary model invocations for deterministic help/status/control forms and delays stop operations.
- Hash text as delivery identity: collapses distinct identical requests and cannot distinguish edits or retries.
- Let Scout approve matching work: turns untrusted interpretation into authority and bypasses protected ledger evidence.
- New hosted service/store or mandatory VM for intake: unnecessary dependencies; existing private contracts and task isolation meet the bounded initial scope.
- Generic Slack/GitHub intake now: exceeds approved authenticated source and privacy scope.

## Consequences

Three independently useful phases establish complete local guarded intake, then authenticated encrypted Slack integration, then neutral adoption/full matrix proof. Native CLI capability and adopter private policy remain explicit enablement prerequisites. No production/model call is needed for implementation tests: actual subprocess fake CLI fixtures demonstrate adapters without certifying a live runtime. Additive storage needs preservation/size checks and guarded rollback; it never silently drops unresolved state. Ordinary local filesystem control remains outside the claimed privileged boundary.

## Evidence

`specs/active/050-request-intake-router.md`; existing `factory-ledger.py`, `factory-routing.py`, `factory-bounded-process.py`, `factory-slack-feedback.py`, `factory-hosted-feedback.py`, `factory-encrypted-feedback.py`; `.claude/hooks/skill-router.sh` explicitly calls itself a hint overlay.

## Native compatibility amendment

The primary hooks documentation exposes no human-origin field and includes generated callbacks; default hook failures continue. Therefore native payload origin claims are not accepted. A trusted console entry records identity before foreground print-mode session/resume delivery, suppresses ambiguous/generated reintake and blocks enablement absent observed ordering and fail-closed behavior. The separate assessor argv is explicitly pinned alongside the primary planning profile; task worker wrappers and safe-mode alone do not establish tool-free assessment. See official https://code.claude.com/docs/en/hooks and https://code.claude.com/docs/en/cli-reference.

## Worker guard refinement

Native safe-mode suppresses project hooks, so an enabled mandatory mutation path uses an opt-in pinned wrapper whose safe-mode contract means clean configuration. It launches native Claude with protected absolute fail-closed guards, narrowly supervisor-minted current task/action/fence references and a guarded read/write tool surface. Direct old safe-mode profiles remain unsupported for mandatory coverage; disabled legacy behavior remains compatible. Execution stays behind existing isolated acceptance boundaries, and the wrapper creates no OS sandbox. Guard ordering/failure and identity propagation need actual pinned-runtime observation before enablement. This refinement implements approved AC-6 rather than expanding source or activation authority.
