# T-283 — retained report-only proof reconstruction

Local implementation of approved Spec014 AC1/2/6/8. Main `6606a1b3392bc8f867b46e5b1e81bbf86be34d6e` was merged as `33cdad9` without rebasing; original T275–282 commit/evidence anchors remain reachable, and main's completed T291 is preserved. Analyze014 remains PASS. This is fixture proof, not live archive activation or a hosted writer permission claim.

`red.log` records the missing retained projection entry after an actual receipt artifact fixture is marked expired and live authentication rejects it. `green.log` records 20 scenarios using real disposable Git objects/ref updates, original ZIP/source material and fresh SQLite. The added explicit legacy-import route has its own actual pre-change failure in `legacy-red.txt` (unsupported explicit mode) and the same final green command covers it. No artificial production regression was introduced to manufacture RED.

Reconstruction authenticates reviewed bootstrap/protection/ancestry before consuming bounded indexed data, revalidates every record and material binding, and rechecks the origin before committing reporting facts. A source Actions API call is not needed after retention. Current revoked/removed profiles receive a withdrawn annotation without rewriting historical delivery/provenance. Revised cancelled runtime tasks remain unchanged; raw encrypted feedback does not enter the projection. Missing material, tampered blob, changed protection, foreign privacy and conflicting historical facts fail atomically. Explicit legacy mode requires the external reviewed document and exact source revision; matching revocation blocks both modes and a failed profile never falls back.

Commands actually run:

- `bash .claude/scripts/test/factory-receipt-retained-proof.sh`: 20 scenarios PASS; final ledger GREEN.
- Receipt CAS: 11 actual Git scenarios PASS after the mode change.
- Bootstrap: 15 cases; state paths: 29 cases; compact archive: 31 cases; existing projection: four AC groups; revocation: 18 cases; coordinator: 63 cases, all PASS (`regressions.txt`).
- Profiles: 33 cases PASS (`final-profiles.txt`).
- Python compilation PASS with temporary cache outside the checkout.
- Structural validator PASS with four pre-existing warnings (`structural-results.txt`).

Limits remain explicit: at most 128 retained segments and 32 MiB checked observations per projection; no silent truncation or automatic pruning. T284 must provide resumable protected chain/discovery anchors and index-first known-proof reuse before attempting source authentication; these controls are invocation limits, not claimed indefinite capacity. T288 must wire fixed protected trust inputs and annotations into reporting loaders. Current live reporting/feedback, credentials, flags, rules and workflow permissions are unchanged. T284–290 remain pending.

The whole-repository ledger checker was also run (it ignores a positional task argument). T283 was content-valid, but the aggregate gate failed on pre-existing T277: red/green commands differ and timestamps are equal. This is not a full-ledger PASS; T277 needs a separate honest metadata/evidence correction before aggregate release. No T277 evidence was modified by this task.
