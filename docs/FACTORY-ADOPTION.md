# Reusable factory adoption

The harness supplies engineering workflow, protected verification/merge contracts, runtime recovery, optional delivery reporting and feedback contracts. New and existing repositories supply their own approved specs/tasks, identity, stacks, credentials and deployment profiles. `qyndex/claude-init` is the distribution source, not the required adopter repository or Slack destination.

Spec 033 replaces broad overwrite/no-clobber reconciliation with transactional ownership. Run from a Git repository root; linked worktrees are supported. The wrapper rejects dirty targets unless YES=1. Choose a branch/tag/full SHA with CLAUDE_INIT_REF; unavailable refs do not fall back. Sources must be clean Git checkouts with tracked process files. No archive overlay or target-owned setup execution is used.

Managed process code/templates and source SHA are recorded in `.claude/install-manifest.json`. Existing foreign content with different bytes blocks adoption before target writes. Upgrade requires UPGRADE=1 (or --upgrade), and every previously owned file must match its recorded hash and mode. Customized/deleted owned files block instead of being overwritten; review their differences explicitly. Same basename does not establish ownership. Root README, user local settings, actual memory, state, rules, active specs/plans/tasks, source policy and pilot workflows are excluded. Generic template files are allowed. Empty adopter ledgers/memory are seeded only if absent, and are not claimed as upgrade-owned process files.

Required local tool checks run before mutation unless SKIP_SETUP=1. They do not install packages, execute setup.sh, apply rulesets, dispatch workflows or activate credentials. GitHub workflow/protection configuration is a separate reviewed per-adopter step. Local installation is not factory, stack or production readiness. Each adopter must configure repository identity, approved specs/tasks, actual stack commands and independent proof identities, reporting destination/state and production adapters. Unsupported or unproven profiles remain blocked.

The default recovery journal directory is `~/.local/state/claude-init/adoption`. Set CLAUDE_INIT_STATE_DIR or --state-root to a canonical absolute private 0700 directory outside the target; journals are owner-only 0600. They contain exact before/after bytes, so keep them outside Git and retain them for the desired recovery window. Do not publish them or copy them into CI artifacts. Process changes use atomic file replacement and an intent journal. A recoverable write failure restores exact previous images; unknown later changes leave recovery blocked rather than destroying them. A per-target OS lock serializes installer invocations.

Use a trusted pinned checkout for recovery:

```bash
bash <factory-clone>/.claude/scripts/reconcile-claude-dir.sh --into <repo> --state-root <private-directory> --revert <journal-id>
# For an interrupted pending installation:
bash <factory-clone>/.claude/scripts/reconcile-claude-dir.sh --into <repo> --state-root <private-directory> --recover <journal-id>
```

Completed revert requires all recorded after-images; pending recovery permits each exact before/after image. Later edits block before any restore. Created files are removed individually and created directories only when empty. History stays private; no recursive .claude deletion occurs. Earlier historical backup formats require manual file-level review. The manifest is an ownership record for local upgrades, not a trusted merge/release authorization receipt.

Remaining F-07 work: neutral typed configuration/capability routing, quota recovery, evidence privacy/retention and rollout metrics. Live independent proof and each target's activation remain separate.

Reporting is optional per adopter. Configure its default-branch workflow, exclusive reporting runner policy, persistent private state and environment credentials using FACTORY-REPORTING-SETUP.md. The qyndex environment/channel/team record is an optional pilot record and must not become installer defaults. No target deployment or Slack send is performed by these installation fixtures. Production release support likewise requires each adopter’s separately proven service/metrics/rollback adapter; copying the harness never enables production autonomy.
