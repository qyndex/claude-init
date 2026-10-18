# Operational CI repair — incomplete acceptance

Source commit: `2ac63e3bb0056ba039bccc19e431d769643ee064`; base: `edd33825d5191f3ad82fc8c9892cebff2dc69686`. The accompanying manifest binds all seven source/test files. No task, spec, workflow, policy, profile, live protection or activation setting changes.

## Reproduced defects and repair

An incomplete origin capsule discarded an older authenticated completed-prefix optimization. An actual current-source GET-only queue reproduction exhausted its unchanged 512-request limit before journal/Slack access. The repair follows actual publication parents, authenticates each capsule with the existing complete validator, and requires the older completed frozen head to match the asserted prior prefix. A bare prior hash earns no credit. Every current-head suffix edge, mutable-policy/ref check and existing request/byte bound remains enforced.

The transport previously accounted empty failed-provider stdout as an invalid successful response size, masking the underlying API failure. Failed calls remain charged; nonempty failed stdout remains charged. Only a bounded numeric HTTP category is extracted, and it controls no retry or authority. Feedback/alerts emit fixed stage/class categories. Diagnostic import/helper failure uses a fixed fallback so chained exceptions cannot expose private text.

## Actual validation

- New real-Git origin regression: PASS. Forty-eight historical commits and two incomplete publications reuse an authenticated completed prefix in 59 fixture GETs; unchanged source exceeded the fixture's 128-read cap. Missing/mismatched/tampered proof, dangerous intermediate state and cycles reject.
- New diagnostic regression: six tests PASS, including actual child CLI execution, separate imports, provider-output secrecy and deliberate diagnostic import/helper failure with private canaries.
- Existing protected transport suite: 53 cases PASS with process-inspection permission. Initial sandbox `/bin/ps` denial also reproduced on unchanged source; it was not waived or fixed by weakening cleanup.
- Existing completed-origin and origin-no-write regressions PASS, including unproven partial fallback, policy/ref races and CAS/uncertain-ack behavior. ShellCheck, compile, whitespace and component scoped Gitleaks checks PASS.
- Independent read-only review of both exact component source hashes found no actionable blocker; an initial diagnostic-fallback privacy finding was fixed and re-reviewed.
- Collectors014/029/035 each ran their own full unskipped `verify.sh`: each smoke exit0. Each collector still exited1/FAIL because no current whole-spec AC-tagged result set was emitted. `check-local-evidence.py` also exited1 with `incomplete AC counts`. Coverage is unknown. No full acceptance or final-head native CI success is claimed.

## Current public-state diagnostic boundary

Patched read-only queue composition reached the preserved fresh-ref guard after 88 GETs when the state actually changed during verification. It performed no mutation or Slack call. This is neither a same-state performance benchmark nor delivery/health PASS. Native historical feedback/alert failure causes remain unknown; the generic old logs do not establish credential, rate-limit or key-format causes.

## Preserved collector output

The three `collectors/<id>/` directories contain the collector files byte-for-byte. Their original invocation paths name absent AC results; no such results were generated or invented. The output was relocated to preserve pre-existing dated evidence at its original paths. Empty attempt directories were not retained. FAIL and unknown coverage remain visible.

## Remaining gates

Keep the candidate a draft under the PR-body skill. New current-head CI, protected-source maintenance approval and native verification remain pending. No budget increase, checkpoint reset, private data read/decryption, secret export, App mint, Slack delivery, dispatch or authority change occurred as part of this repair. Roll back source through a reviewed revert of the eventual merge commit; never reset durable reporting state.
