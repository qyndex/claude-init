# Adopter quickstart

## Prerequisites

Choose an immutable, reviewed harness source revision. Use a clean source checkout at that revision, Python 3, Bash and Git. Back up and review the target repository's existing content before adoption. Each repository owns its protected configuration and secrets.

## Dry-run adoption

Run these commands from the reviewed harness checkout. Preview the transactional installer against a new or existing target:

```sh
python3 .claude/scripts/factory-adopt.py --from /path/to/reviewed-harness --into /path/to/target --dry-run
```

Review the proposed files and conflicts. The installer preserves existing repository content and refuses incompatible managed files; resolve conflicts before applying adoption. Keep the source pinned to the same reviewed immutable revision when applying it. Installation alone does not enable services.

## Protected readiness

Validate the target's separately reviewed protected policy:

```sh
python3 .claude/scripts/factory-preflight.py --policy /path/to/protected-policy.json
```

Missing prerequisites block activation. Structural preflight does not prove credential usability, available model capacity or independent execution. Installation does not enable merge authority, reporting or production. Provision each repository's own main-only environments, App installation, approved specification and runtime pins, and secrets; verify real independent evidence before enabling authority.

## Delivery and acceptance

Treat engineering verification, merged delivery and product acceptance as distinct milestones. Independent reviewers and tests prove the approved specification; an authenticated receipt records a merge; operator feedback establishes product acceptance or creates a separately approved amendment.

Production requires the target's actual deployment backend, health checks, SLO, known-good baseline and rollback proof before automated releases. A harness fixture does not establish a service's production readiness.

See [Adopter setup](FACTORY-ADOPTER-SETUP.md) and [Factory activation](FACTORY-ACTIVATION.md) for protected setup and the ordered rollout gates.
