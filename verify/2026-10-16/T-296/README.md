# T-296 — bounded protected administrative observations

Implements Spec010 AC5's neutral validation/capture helper only. It is not yet
wired into coordinator/workflow; T297/T298 and aggregate T292 remain pending.
No live API observation, configuration, credentials, permissions, settings, flags,
source pins, native signature or hosted shadow receipt is claimed.

Actual first RED is the new behavioral acceptance invocation against the absent
helper, captured before implementation. Final GREEN runs the same command and
checks 60 cases: direct empty actors, hidden exact approval, strict schema and
identity, actor/missing/foreign/drift/future/settle negatives, duplicate/nonfinite
and oversized JSON, fractional-timezone precision, and actual disposable gh
process fixed-GET arguments plus bounded output rejection. Capture v1 explicitly
records bypass_actors: []; malformed/nonempty approval actors cannot substitute.

The full semantic projection retains exact timestamp strings and nested rules/
conditions, rejecting unknown top-level metadata. _links and the caller-specific
current_user_can_bypass are excluded. Equivalent alternate timestamp spellings
conservatively invalidate the metadata hash; no subsecond truncation occurs.
Repository IDs are fetched, never inferred from names. Protected input trust is
an integration responsibility of T297, not conferred by arbitrary caller JSON.

captured-metadata.txt records compatibility with the actual public ruleset shape;
repository ID42 was deliberately a fixture and no activation approval was emitted.
coordinator.txt: unchanged coordinator regression,63 cases passed.
ledger.txt: actual TDD ledger gate,0 failures/0 warnings,70 legacy incomplete.
structural.txt: actual structural check passed with4 existing warnings.
Python compile passed. Transport uses the existing bounded-process stdlib helper
(timeout30seconds, aggregate262144bytes); it remains an explicit transitive
runtime dependency already pinned before the new helper is integrated.
