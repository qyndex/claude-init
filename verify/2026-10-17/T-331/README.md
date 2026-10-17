# T331 — bounded explicit reporting credential roles

The canonical genuine RED rejects the missing transport before production code.
Supplemental actual REDs identified a `per_page`/`page` substring collision and
unsafe short-page completion with a smaller requested page size. Both are fixed;
47 focused offline subprocess cases pass. The original sandbox oversize-output
attempt failed because `/bin/ps` cleanup inspection was denied; its log is retained.
The same actual suite passed with escalation for owned process cleanup only.

The new router uses fixed GitHub.com endpoints, sanitized subprocess environments,
2 MiB per response and one shared 2048-call/32 MiB envelope across REST, fixed Blob
and fresh PR queries. It manually meters bounded pagination, rejects a saturated
1000 filtered count and inconsistent counts, and does not invoke unmetered gh
pagination. It is a transport, not a source/history completeness proof.

Actions/source/PR reads use the workflow credential; repository/policy/Git state
operations and archive Blob queries use the selected state credential. Generic
GraphQL, policy/Actions/PR writes, foreign/traversal endpoints, deletes and forced
ref updates reject before IO. Existing exact fixed query implementations remain
responsible for complete selector/repository/object/merge validation. Raw batch
responses charge the enclosing transport once; malformed queries never fall back.

App mode is default off. Explicit true requires the separate App ID/token and
never falls back. Legacy mode alone preserves the optional legacy state token or
workflow-token fallback. The config contains no credentials. No live credential,
App installation/private capability or policy cutover is claimed. Existing loaders
and workflows are deliberately not wired until later T332–T335.

The fixed Blob and PR adapter regression suites also pass (50 and 38 cases).
Compile, ShellCheck, ledger, structural validation and commit checks are recorded
separately. T333 renderer path union is planning ownership only; it remains pending.
