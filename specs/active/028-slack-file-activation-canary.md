---
id: 028
slug: slack-file-activation-canary
status: approved
owner: "@codex"
created: 2028-10-10
updated: 2028-10-10
complexity: S
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Isolated live attachment canary

Authorized F-05 activation refinement: verify the actual file transport with a small labelled canary, without changing daily reporting state or inventing merged features.

## Acceptance criteria

1. **AC-1**: Use the real attachment adapter to upload explicitly labelled isolated canary bytes and authenticate exact private file receipt; retain bounded receipt evidence.
2. **AC-2**: A fresh invocation or retry verifies the existing exact receipt without allocating or sharing another file.
3. **AC-3**: Allocation requires first attempt of the sole known manual canary run on the configured default branch. Previous, ambiguous or lost-response runs without receipt block, while a visible original receipt reconciles without reallocation. Preserve history as the allocation fence.
4. **AC-4**: Disabled attachments, foreign repository and missing grants block before allocation. Protected manual workflow shares reporting concurrency, uses read-only Git permissions and configured adopter workspace/channel, and never mutates daily digest state. Local fixture and reporting regressions pass; live proof requires the protected dispatch and repeat.
