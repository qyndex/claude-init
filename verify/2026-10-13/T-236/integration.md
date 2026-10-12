# T-236: Continuation controller integration characterization

Canonical acceptance: `bash .claude/scripts/test/factory-request-intake.sh continuation-freshness`.

The aggregate selector invokes the existing four scoped fixtures in separate actual Python subprocesses. Their private SQLite stores, controlled Git repositories, bounded fake native assessor processes and controller APIs exercise implemented behavior from T-263–T-266. This is a verification-only characterization: the first acceptance run passed without production changes. `green.log` records the actual command and outcome; the supported `characterization` marker explains the green-only exemption. No failing RED was manufactured.

| Fixture selector | Cases demonstrated |
| --- | --- |
| `session-continuation` | Explicit eligible task selection; bare continuation bound to the same session; unbound/global/foreign-session work clarifies; outstanding proposal/blocked/unresolved context dominates; completed tasks cannot resume. |
| `clarification-revisions` | Immutable proposal history; clarification supplements and source edits supersede; same-thread reply/edit advances only the current head; retry tokens remain bound/idempotent; stale, foreign, unresolved and blocked parents reject; unrelated scope stays separate. |
| `decision-freshness` | Fresh decisions accepted after restart; absent snapshots and pending requests blocked; changed request identity/revision, uncited source bytes, candidate HEAD/ref, evidence, approvals, plan, eligibility and protected pins revoke permits; superseded/blocked proposal heads reject; explicit/status/bare continuation preserves independently derived session evidence; historical records remain readable without rerunning assessment. |
| `approval-eligibility` | Approval requires a valid unambiguous first frontmatter block with exact plan-spec binding; body-spoofed, duplicate, malformed and unresolved numbered-question scope cannot execute; legitimate quoted/comment/CRLF headers remain supported; intake/global pause and missing/corrupt control fence current permits; resumed valid scope becomes eligible without provider execution. |

Every fixture asserts controller outcomes and absence of unauthorized effects. Fake-process assessment proves the controller's bounded subprocess contract, not live provider readiness. The aggregate selector does not invoke Claude, APIs, Slack, GitHub, activation, task dispatch, implementation mutation or delivery.

This evidence covers controller behavior and its private continuation/freshness contracts. Phase 1 console launch, native hook correlation, proposal publication, controller action reservation, ledger dispatch and worker mutation guards remain separate pending tasks. It does not establish complete AC-1/AC-6/AC-13 source-boundary coverage or full spec-050 completion.
