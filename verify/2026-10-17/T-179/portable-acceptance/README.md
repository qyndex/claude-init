# Portable historical bootstrap acceptance

The original missing-input failure is retained under verify/2026-10-17/publication-gates/. The task now defaults its non-secret PR selector to the already-recorded bootstrap PR50 URL. An explicit FACTORY_ACTIVATION_PR override remains supported; the exact immutable merged SHA requirement is unchanged.

The actual command passed against GitHub with FACTORY_ACTIVATION_PR absent. This is historical bootstrap bookkeeping only. Full candidate verification, T318 replay repair, T180 activation and public publication remain pending. No task status, producer authority, workflow, security policy or live setting changed. This isolated follow-up does not alter the frozen 8cf5d8f upload proposal.
