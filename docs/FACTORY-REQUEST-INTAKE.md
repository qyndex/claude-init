# Factory request intake: coverage and boundaries

Spec [050](../specs/active/050-request-intake-router.md) is approved. This document records the implemented foundation and assembled worker fixture; it does not certify live native capability or activate intake. Installation remains neutral and disabled by default. Missing adopter identity, protected configuration or observed runtime prerequisites blocks governed work.

## Current coverage inventory

| Boundary | Implemented fixture coverage | Operational status |
| --- | --- | --- |
| Private controller | Distinct human submission identities, exact retry tokens, stateful continuation and proposal lineage; bounded Scout collection/assessment; approval and freshness checks | Direct protected APIs tested; no universal prompt interception |
| Proposal publication | Assigned private draft path, literal untrusted data, exclusive writes and exact recovery | Cannot approve or enter wider execution scope |
| Task enqueue and claim | Fixed account installation registry, protected pins, current approved task/request, unique start identity and owner/fence CAS | Mandatory direct native launch remains blocked pending console/dispatch assembly |
| Protected worker prompt | Supervisor-derived private descriptor; one-use exact prompt/session/cwd submit callback | Actual fake-native plus hook subprocess fixture; no human intake allocation from callbacks |
| Worker Read | Explicit selected context or exact completed own output | Broad source scope and inventory metadata do not grant disclosure authority |
| Worker Write/Edit | Exact approved path and bounded intended postimage; durable intent before native tool permission; independently observed post bytes and acknowledgment | Unknown effects fence subsequent actions; no blind retry |
| Worker completion | Successful bounded transport, confirmed group cleanup, exact session/model usage, current owned authority and resolved effects | Runtime completion only; engineering verification remains false |
| Guarded foreground console | Planned T-244 | Not implemented or enabled by T-243 |
| Explicit authenticated Slack feedback bridge | Existing private feedback contract; intake integration planned separately | This fixture does not prove its entry coverage or authorize generic Slack capture |
| Bare CLI, IDE/filesystem edits, other agents and tools | Outside this mandatory coverage | Advisory or unsupported; editable local hooks are not a privileged OS boundary |

The assembled acceptance command is:

```sh
bash .claude/scripts/test/factory-request-intake.sh hooks
```

It runs the protected wrapper, a pinned fake native executable and actual absolute hook subprocesses. The positive journey consumes the bound prompt, reads selected context, writes a new approved file, acknowledges it, reads that own output, edits it and acknowledges the exact observed bytes. Independent fixture assertions check actual files, two completed mutations/acknowledgments, the private semantic receipt and unchanged engineering task state. Negative journeys reject unselected disclosure, outside-scope mutation, a foreign native session and failed/missing post acknowledgments. Callback replay does not permit another write or native launch. A missing-post journey emits misleading native success, remains fenced, then reconciles the exact bound post callback through the actual hook subprocess; wrong callbacks reject, exact duplicate acknowledgment is harmless, and actual bytes and launch count remain unchanged. Other worker suites cover absent/crashed/invalid/timed-out hooks, malformed results and cleanup under wrapper loss/backpressure.

## Enablement prerequisites

Each adopting repository owns its private policy, profile, installation registry and state. Required helper/executable/interpreter/settings observations must match the protected source closure before execution. The worker uses only the protected primary implementation model and a dedicated implementation subscription credential; it has no reviewer/controller credential, fallback model or automatic retry.

Supported mandatory native behavior requires an observed runtime version at least **2.1.295** with synchronous `UserPromptSubmit`, `PreToolUse`, `PostToolUse` and failure callbacks, including **`onFailure: block`**. Missing hooks, exceptions, invalid responses and timeouts must actually block in that runtime. Fake fixtures prove this adapter contract; they cannot certify a real native executable's ordering or failure semantics. Record those observations before enabling mandatory launch. See the official [hook contract](https://code.claude.com/docs/en/hooks), [CLI reference](https://code.claude.com/docs/en/cli-reference) and [memory controls](https://code.claude.com/docs/en/memory).

The wrapper's clean mode creates private cwd/HOME/config directories, pinned absolute settings and callbacks, empty MCP configuration, disabled auto memory and unmanaged instruction exclusions. It does not forward native `--safe-mode`, because native safe mode suppresses project hooks. Managed-policy compatibility and unmanaged instruction exclusion also require actual runtime observation.

Every claimed task receives a supervisor-issued fresh native session and immutable descriptor. A descriptor binds the actual task revision, request revision, owner/fence, model and prompt digest. It is consumed once and cannot be reused to allocate another human request. Human console sessions and ordinary prompt dispatch remain a later assembly step.

Current finite bounds are at most 20,000 request characters, 500,000 collected context bytes, 64 KiB combined process output and 60 seconds per assessment or guarded worker turn. Adopters can choose stricter protected limits. Cleanup has a separate finite grace; limits never silently truncate or authorize another model attempt.

## Privacy, recovery and evidence

Raw requests, context, prompts, native stdout/stderr and semantic receipts stay in owner-only private storage outside candidate and authority repositories. Public projections must remain sanitized under the adopter's existing privacy contract. Explicit authenticated private Slack feedback approval does not authorize general channel ingestion.

A receipt binds private transport and effect hashes, exact native session/model usage and current approval/ref/lease/pause controls. Model narrative is untrusted data: it cannot approve scope, reconcile an uncertain write, prove tests/spec compliance, merge or deploy. Reported cost estimates are not actual subscription spend.

Successful transport is retained even when later semantic validation is paused. Unknown launch/effect outcomes fence replay. Recovery observes exact recorded effects under fresh authority; it never starts a second native process or blindly repeats a write. Current-authority checks remain necessary when validating an existing receipt.

T-243 is characterization of existing T-267–T-272 production behavior. Its assembled test is not a fabricated red/green implementation pair, full spec-050 completion, live activation, native capability certificate or engineering delivery proof.
