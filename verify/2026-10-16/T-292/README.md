# T-292 — aggregate local verification

T296–T298 implemented the approved Spec010 AC5 repair. This aggregate task is
verification, not a new production implementation. The first current aggregate
acceptance already passed; current-first-pass.txt preserves that actual output.
Original feature fail-first evidence remains under each child task (including the
T297 failure-invalidation review fix). No current production mutation forced RED.

The canonical aggregate ledger uses a retrospective historical replay AFTER
implementation, following the approved test-only verification precedent. Unchanged
current test files were copied to a detached6606 protected-source checkout; their
SHA256 values, exact CWD and revisions are in historical-inputs.txt. The actual RED
is missing observation implementation on that historical source, not a missing
test script, syntax failure or network error. The same exact acceptance command
and test bytes pass on source1bc46b7. GREEN was rerun at an actual later second to
satisfy strict ledger order. This is NOT claimed as original feature TDD chronology.

Fresh actual shell subprocesses recorded six command outputs/hashes and source
commit1bc46b7 in the Spec010 results.json. AC1–5 mappings refer to those actual
commands: source/candidate/runtime, sandbox argv/output contract, bounded fake
reviewer process, latest immutable run plus injected certificate/digest proof,
and administrative observation/ingress/failure-invalidation/final-drift fixtures.
The approved collector --check-only consumes those freshly generated manual shell
runner results; it did not manufacture a native stack run. Its smoke verifier also
executes. This repo has no application browser journey or configured native stack
runner. No passing fixture is described as an independent or hosted attestation.

The source repair is locally implemented and tested only. Spec010 remains approved;
T180/T222 live proof, actual protected operator observation, current-source hosted
shadow and private-adopter prerequisites remain separate and unresolved here.
Administration read, merge_enabled:false, authority settings and live protection
are unchanged. The branch is not pushed. Git history remains anchored to actual
protected main6606; no receipt continuation commits or activation packages changed.

Gitleaks actual candidate-reachable full history scanned151commits with no findings.
Commitlint/trailer checks passed for the source branch. Final local evidence gate
and collector output are retained alongside this report; they confer no merge or
production authorization. Separate nine-check CI and concrete operator-reviewed
maintenance are still required before landing.
