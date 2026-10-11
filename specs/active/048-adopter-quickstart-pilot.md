---
id: 048
slug: adopter-quickstart-pilot
status: approved
owner: "@codex"
created: 2026-10-11
updated: 2026-10-11
complexity: S
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Controlled adopter quickstart pilot

One noncritical documentation feature exercises genuine independent verification, review, shadow eligibility, delivery, digest and later operator feedback. Publishing these bytes requires the concrete operator decision. Production and automatic merge remain disabled until their separate proof and decision gates.

## Acceptance criteria

1. **AC-1**: Add docs/FACTORY-ADOPTER-QUICKSTART.md with Prerequisites and Dry-run adoption sections. Show the real transactional factory-adopt.py --from /path/to/reviewed-harness --into /path/to/target --dry-run command, immutable reviewed source requirement and preservation of existing repository content. Examples use adopter placeholders, without qyndex account, Slack or App identities.
2. **AC-2**: Include Protected readiness with factory-preflight.py --policy /path/to/protected-policy.json, explaining that missing prerequisites block and installation does not enable merge authority, reporting or production. Each adopter owns protected configuration and secrets.
3. **AC-3**: Include Delivery and acceptance explaining that engineering verification, merged delivery and product acceptance are distinct. Production requires target-specific health/SLO and rollback proof. Link FACTORY-ADOPTER-SETUP.md and FACTORY-ACTIVATION.md.

## Allowed candidate scope

Only docs/FACTORY-ADOPTER-QUICKSTART.md. T-222 is the future implementation/delivery identity. No implementation is included in this preparation package. The spec revision and complete AC commands must be approved on the protected base before opening factory/spec-048/adopter-quickstart. Feedback later creates its own approved amendment and candidate; do not pre-authorize that unknown scope.
