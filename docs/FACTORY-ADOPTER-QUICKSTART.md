# Factory adopter quickstart

Use this harness with a new or existing Git repository. Start with a reviewed installation; activate each factory capability only after its own protected readiness checks pass.

## Prerequisites

- Choose an immutable, reviewed harness commit. Keep its checkout outside the target repository, verify its full commit SHA and keep the source worktree clean. A moving branch name is not a reviewed revision.
- Have Git and Python 3 available. The target path must be the root of its own Git repository. Review and preserve its existing application files, specifications and customizations.
- Identify the adopter's operator and protected configuration location. Each adopter owns its repository policy, App installation, reporting destination and secrets; copying the harness does not supply these.

## Dry-run adoption

From the reviewed harness checkout, inspect the transactional adoption proposal first:

```sh
python3 .claude/scripts/factory-adopt.py --from /path/to/reviewed-harness --into /path/to/target --dry-run
```

Confirm the returned source SHA matches the immutable revision you reviewed, and review the proposed file count. The dry run does not apply target file changes. Adoption preserves existing repository content: conflicting unmanaged files block adoption rather than being overwritten. Resolve a conflict deliberately before proceeding; do not unpack the whole harness over an existing repository.

After reviewing and approving that exact source/target proposal, apply using the same immutable clean source and an absolute private journal directory outside the target:

```sh
python3 /path/to/reviewed-harness/.claude/scripts/factory-adopt.py --from /path/to/reviewed-harness --into /path/to/target --state-root /private/path/adoption-journals --check-tools --dry-run
# Review this final proposal and tool checks, then apply the same transaction:
python3 /path/to/reviewed-harness/.claude/scripts/factory-adopt.py --from /path/to/reviewed-harness --into /path/to/target --state-root /private/path/adoption-journals --check-tools
```

The journal root must be canonical, private 0700 and outside the target; journals contain exact before/after bytes and must stay outside Git and CI artifacts. For existing owned installations, use the [reviewed upgrade and ownership rules](FACTORY-ADOPTION.md#reviewed-keep-local-configuration-upgrades), not an overwrite. Follow [Factory adopter setup](FACTORY-ADOPTER-SETUP.md) for protected configuration and repository-specific setup. Review and commit the resulting target changes. Installation alone does not activate a factory capability.

## Protected readiness

From the installed target repository, run preflight against that adopter's protected policy:

```sh
python3 .claude/scripts/factory-preflight.py --policy /path/to/protected-policy.json
```

Missing prerequisites block activation. Installation does not enable merge authority, reporting or production. Keep protected policies and secrets outside implementation access, and configure each repository's own protected environments and identities. A successful installation or another repository's pilot is not proof of readiness for this adopter.

Follow [Factory activation](FACTORY-ACTIVATION.md) for the independently verified evidence, shadow checks and reviewed activation sequence. Preserve the required approval boundaries; a preflight report is not permission to enable a capability.

## Delivery and acceptance

Treat engineering verification, merged delivery and product acceptance as distinct outcomes. Independent verification checks a candidate against its approved specification. A merged delivery needs its actual merge identity and authenticated receipt. Product acceptance follows the operator's review and feedback; feedback that changes scope needs its own approved amendment and delivery cycle.

Production additionally requires the adopting service's target-specific health checks, SLO evidence and rollback proof. Configure and verify that deployment adapter before enabling autonomous releases. A generic harness installation does not certify a production service.
