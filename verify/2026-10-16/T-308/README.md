# T308 — protected derived-fact stages

Actual RED ran after real Git archive/checkpoint setup and failed because the
protected staging API did not exist. Only afterward was stage_projection added.
The first GREEN attempt reached the shared2048-call budget while repeatedly
reauthenticating immutable Git objects; its actual failure remains in
initial-capacity-failure.log. Limits were not raised. An invocation-only cache of
exact40SHA Git commit/tree/blob responses shares the existing32MiB observation
budget and returns decoded copies. Mutable refs/rules/PR responses and local
approval/trust documents remain freshly observed. Final GREEN has17 case groups;
original six-case, eleven-case and thirteen-case successes were actual intermediate runs.
Root review then found Python equality accepted stored schema_version:true as1.
The original RED and pre-schema GREEN are retained separately. A new actual RED
tampered the protected stage schema to True; minimal canonical-JSON equality now
rejects boolean/float integer impersonation while permitting key ordering and
whitespace differences. Final tests cover True/1.0 in both stage and index schemas.

The real Git fixture proves stage/index atomic publication, concurrent-writer
CAS retry, lost-ref-ack reconciliation, a separate reader object's idempotent
restart, cross-window task conflicts, strict selectors/no caller-fact argument,
missing time without advancement, changed exact time rejection, malformed stored
execution index rejection, symlink/SQL path rejection, and mutable protection/head
changes despite immutable-object caching. Fresh hosted SQLite reconstruction is
T309, not established by an object restart here. No process-restart claim is made.

Facts derive only from independently authenticated T306/T301 publication lineage,
retained source/material proof and T307 exact same-repo PR merge-time observation.
A bounded slice (at most8 references) and its task/execution indices share one
observed-base commit. Indices are global within one frozen interval/trust campaign,
not all historical campaigns. Existing values must exactly equal recomputed
complete documents: hashes or stored JSON alone never authorize source facts.
Missing time stays a retryable explicit gap. Other report and encrypted-feedback
blobs remain opaque and preserved. No SQLite serialization, SQL, caller-supplied
facts, task creation or runtime credit is accepted.

All API calls/observations share2048 actual calls/32MiB per invocation and at most
three CAS attempts. Capacity or uncertain acknowledgement fails closed. Strict
sharded inert stage paths avoid an ever-growing single manifest; no archive is
pruned. The existing256-ancestor origin limit remains pending T310; no complete
coverage, hosted large-history readiness or live exclusive-writer capability is
claimed. T309 must reauthenticate retained materials and current revocation before
consuming these stages. No credentials/settings/permissions/push/live activation
were changed.
