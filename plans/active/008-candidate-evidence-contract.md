---
id: 008
slug: candidate-evidence-contract
spec: specs/active/008-candidate-evidence-contract.md
status: approved
owner: "@codex"
created: 2026-10-09
updated: 2026-10-09
---

# Candidate evidence contract implementation

Use a strict, versioned JSON contract and Python standard-library validator. Resolve expected identities, check producers and exact AC sets from a separate protected context. Reject missing/extra fields rather than treating null or missing arrays as clean. Keep this core separate from legacy evidence until the authenticated coordinator can supply authoritative context and receipts.

- T-175: AC-1 through AC-4 validator, fixtures and integration requirements.
