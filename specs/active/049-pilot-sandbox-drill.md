---
id: 049
slug: pilot-sandbox-drill
status: approved
owner: "@codex"
created: 2026-10-11
updated: 2026-10-11
complexity: M
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Prove proposed pilot sandbox feasibility

The operator requested continuing readiness work while Claude review remains paused. This preparation drill does not approve proposed spec048 or activate authority.

## Acceptance criteria

1. **AC-1**: A fixture exercises the exact proposed pilot acceptance argv and immutable image through the actual producer sandbox builder. Positive fixture passes all three commands; each individually defective fixture fails its intended AC. Local execution is labelled host contract coverage, never container proof.
2. **AC-2**: An explicitly enabled nonroot Linux Docker step executes these cases in the pinned image and confirms no network, host credential/socket access, root writes or candidate-mount writes; writable temporary copy works and original fixture bytes remain intact. Missing Docker/image/runtime must fail, not skip when enabled.
3. **AC-3**: CI preserves a nonsensitive source/image/policy-bound result with actual exits and isolation assertions. Generic suite repetition and installed adopters explicitly skip live source-pilot proof; no model invocation, live config change, pilot approval or delivery receipt is produced.
