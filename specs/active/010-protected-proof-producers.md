---
id: 010
slug: protected-proof-producers
status: approved
owner: "@codex"
human_owner: "@operator"
created: 2026-10-09
updated: 2026-10-20
complexity: L
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Protected proof producers

Implementation scope authorized by the operator's instruction to complete the factory plan in dependency order. Completes the producer implementation slice of F-02/F-03. Live activation is a separate gate under spec 009; this specification does not claim an authenticated production or shadow run.

## Acceptance criteria

1. **AC-1**: Protected policy selects the approved spec bytes, complete AC set, path scope and pinned producer runtime. Foreign candidates, authority changes, wrong workflow/event/base and incomplete diffs fail before running candidate code.
2. **AC-2**: Each approved AC executes an explicit argv in a digest-pinned Docker image with no network, credentials, host writes, capabilities or root user. Fresh candidate state, bounded resources/output and exit-code-bound observation digests form the verifier artifact; failed or missing commands cannot emit a passing verdict.
3. **AC-3**: A separate tool-free model reviewer receives complete spec and before/after sources within a bounded input size. An explicitly selected credential route is used, never an automatic metered fallback. Missing/quota-limited credentials, model errors, malformed verdicts and PASS with unresolved findings fail.
4. **AC-4**: Unique candidate-head check receipts retain exact approved App/head/success guards. Authenticate the latest candidate-head run selected by immutable pinned workflow ID before checking event, status or success; never fall back to an older successful run. Verify exact repository/path/head/workflow/event/run/attempt metadata, complete protected source pins, cryptographic attestation and artifact/base bindings. Display URLs and check-suite associations confer no run authority. Missing/ambiguous/latest failed or stale runs reject. Automatic reevaluation resolves the candidate from the completed producer artifact.

5. **AC-5**: When live ruleset metadata explicitly exposes bypass actors, reject nonempty or malformed actors regardless of approval; explicit empty actors remain directly verifiable. Only omitted actors may use a bounded, complete operator observation from protected main-only environment configuration outside canonical policy and Git. Require exact repository/ruleset identity, stable full metadata digest, server update time and observation after a 60-second settle and no later than now. Reject missing, foreign, partial, future or changed observations; continue verifying all live effective pins and strict PR protection. The GET-only operator command must observe actual explicit empty actors. Retained observation audit is administrative evidence, not a native attestation or candidate authority. The stable semantic digest canonicalizes only created_at and updated_at as losslessly supported UTC instants; compare observation/server updated_at by that same exact instant. Preserve all other fields exactly and retain raw timestamps in diagnostics. Reject unsupported submicrosecond precision instead of truncating; a one-microsecond change must invalidate approval. Existing lexical-hash observations require fresh full-GET capture, with no old-hash fallback.

## Activation dependencies

Default producers stay disabled until App installation, reviewed runtime/image/command/spec pins, working reviewer capacity, required check registration and live shadow proof are available. Keep merge_enabled false throughout shadow testing. The operator selected the existing subscription after its quota resets; API fallback is not authorized.

## Approved native-build profile amendment — T345 — 2026-10-20

The operator approved implementation and local verification of optionA in docs/activation/2026-10-20/native-build-profile-proposal.md. This refines AC2 without activating policy or changing its isolation/resource requirements. A registered protected-main per-spec sandbox_profile may select only strict-interpreted-v1 or native-build-v1. Omission remains strict-interpreted-v1 for existing policies. Unknown values, non-string settings or arbitrary Docker-option values fail before candidate execution. Candidate files, event metadata and environment variables cannot select a profile.

Both profiles explicitly preserve networknone, read-only root, UID/GID65532, capdropALL, no-new-privileges, existing seccomp behavior, nosuid/nodev,2GiBmemory/2CPU/pids256,1GiBscratch and a read-only candidate mount without host sockets, credentials or private state. Strict scratch remains noexec; only the separately protected native-build registration makes scratch exec. This removes that defense only for explicitly registered work; the Docker container remains the candidate-code execution boundary. Image/command pins, source/provenance/policy-hash bindings and all existing gates remain unchanged.

Local genuine execution/isolation probes and exact application commands establish only their observed outcomes. A later font-network, dependency, resource or build failure remains failed/pending rather than waived. No registry publication, workflow dispatch, merge, live profile/policy/trust activation, credentials, network fallback or budget increase is authorized by this amendment. Existing failed/unproven observations remain historical.
