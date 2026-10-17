# Same-invocation stage acknowledgement

The actual real-Git first publication test failed before the repair: the stage writer had reconciled its ref, but maintenance returned without advancing offset. Session3548 is the genuine RED. The seven-line repair reloads authenticated GitState after either actual staged or already-staged completion, requires the exact prior maintenance journal bytes, and publishes the offset through the existing nonforced CAS. It grants scheduling progress only; coverage remains false.

Session73188 passed the same positive test. Expanded session76996 passed four actual Git fault scenarios from independently cloned real pre-stage history: staged-write lost acknowledgement, maintenance-offset CAS race with opaque concurrent worker state, maintenance-offset lost acknowledgement, and another maintenance writer acknowledging the same stage before the outer reload. The changed journal rejects the outer write. Every scenario recovers offset1 with exactly one stage publication and preserves encrypted opaque worker bytes.

These scoped proofs do not claim T334 complete, actual Slack/file scopes, timely daily delivery, or a completed saved1001 tail. The previous saved1001 run was deliberately interrupted with130 and preserved its authenticated partial campaign; it was not a runtime RED or PASS.
