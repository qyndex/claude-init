# Proposed native-build verifier profile

Decision only; no source/runtime/policy or live configuration change has been made.

## Actual boundary

The separately built brownfield Linuxamd64 image freshly installs its own430 locked packages offline and launches actual Chromium under the existing producer limits. Exact npm lint and build each exit126 before assertions/compilation. Readback shows correctly0755 target files and /tmp mounted rw,nosuid,nodev,noexec. Source, image and raw observations are in /private/tmp/factory-brownfield-verification-image-20261020. No font/network/OOM/build-success inference follows from this failure. Public ordinary GitHub CI passes; it uses a different execution environment.

## Options

A (recommended): introduce an explicit protected per-repository/per-spec native-build sandbox profile. Only a registered trusted-main policy selects it; candidate content and environment cannot request arbitrary Docker flags. It permits execution in the writable scratch mount for that profile while retaining networknone, read-only root, nonroot65532, allcapabilities dropped, no-new-privileges, Docker's existing seccomp behavior, nosuid/nodev,2GiBmemory/2CPU/pids256/1GiBtmpfs and no host sockets, credentials or private state. The existing strict interpreted profile stays the default. This is suitable for a general software factory that must run dependency launchers and compiled/native test tools. It removes the scratch noexec defense for explicitly selected work; the container remains the code-execution boundary.

B: retain writable scratch noexec and build a separate integrity-pinned read-only native toolchain adapter. Trusted image tools may execute from immutable image paths; mutable installs remain nonexecutable. More framework-specific work is needed for esbuild/SWC/native modules and exact dependency resolution. Do not count symlinked host dependencies, mocked builds or skipped suites as fresh verification.

C: leave brownfield protected native qualification blocked. Existing ordinary CI and draft evidence remain available; no automatic merge/activation credit follows.

## Proposed scope if A is approved

Design and implement a small versioned protected-policy profile selector, preserving old-policy compatibility/default behavior and rejecting unknown profiles/arbitrary flags. Make both profiles' actual mount semantics explicit. Add genuine RED/GREEN policy tamper/default/invalid-profile tests and local Linux positive native-execution plus negative isolation/resource probes. Reuse exact immutable images and clean source/install requirements; do not loosen any other guard or alter application behavior. Keep all incomplete evidence and old observations truthful.

No live deployment, producer/policy activation, protected-main merge, registry publication, credentials, network fallback or budget increase is included in this design/local-verification approval. Any live cutover requires a separate concrete reviewed package. The local build may reveal a later font-network, native-library or storage issue; that remains pending until actually observed, not waived here.
