---
id: 021
slug: hosted-reporting-checkpoints
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
spec: specs/active/021-hosted-reporting-checkpoints.md
---

# Hosted checkpoint plan

Keep SQLite as a private ephemeral projection; persist only typed allowlisted JSON on a protected data-only branch. Validate branch identity, protections, tree/blob integrity and explicit bootstrap SHA before restore. Commit each changed projection with a unique nonce and the previously observed parent, then update the reference with force=false. Uniqueness matters: identical concurrent commits could otherwise share a SHA and both update successfully. Checkpoint uncertainty before external send and receipt/cursor after confirmation. Freeze a failed local projection until a fresh load; no retry/rebase of state writes. Restore through bound SQL inserts, never remote SQL or database binaries. Use the repository Actions token for same-repo pilot state, and optionally a separate state-only token for an adopter-chosen external repository. Keep profiles mutually exclusive and activation off through fixture proof. Bootstrap/protection configuration is separate from delivery; use only public pilot records in this public repo.
