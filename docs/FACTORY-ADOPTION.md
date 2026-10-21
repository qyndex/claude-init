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

Spec 040 distributes pinned encryption requirements, disabled neutral examples and FACTORY-ADOPTER-SETUP.md through explicit version/hash/mode ownership. Configure protected routing using spec 037; no examples activate the factory. Remaining F-07 work includes bounded private evidence/retention and rollout metrics. Live independent proof and each target's activation remain separate.

Reporting is optional per adopter. Configure its default-branch workflow, exclusive reporting runner policy, persistent private state and environment credentials using FACTORY-REPORTING-SETUP.md. The qyndex environment/channel/team record is an optional pilot record and must not become installer defaults. No target deployment or Slack send is performed by these installation fixtures. Production release support likewise requires each adopter’s separately proven service/metrics/rollback adapter; copying the harness never enables production autonomy.

## Reviewed keep-local configuration upgrades

Intentional adopter configuration can transfer to local ownership for exactly root
`CLAUDE.md`, `.mcp.json` and `.claude/settings.json`. This is an explicit reviewed
upgrade, not a force flag. `.claude/CLAUDE.md`, scripts, hooks and framework agents
remain managed; every other customized managed file still blocks the transaction.

Prepare a small private JSON resolution plan outside the target. Its exact bytes
are the review payload; do not publish configuration values or private journals.
The strict schema is:

```json
{
  "schema_version": 1,
  "source_sha": "<40 lowercase hex immutable clean source HEAD>",
  "target": "<canonical absolute target repository root>",
  "repository": {
    "git_common_dir": "<canonical absolute Git common directory>",
    "head_sha": "<40 lowercase hex target HEAD>"
  },
  "manifest": {"sha256": "<current manifest bytes SHA256>", "mode": 420},
  "entries": {
    "CLAUDE.md": {
      "action": "keep-local",
      "owned": {"sha256": "<original ownership SHA256>", "mode": 420},
      "current": {"sha256": "<reviewed target bytes SHA256>", "mode": 420},
      "upstream": {"sha256": "<incoming source bytes SHA256>", "mode": 420}
    }
  }
}
```

Use one to three allowed entries. Fingerprints include decimal POSIX mode values:
420 (0644) or 493 (0755); local configuration may also be 384 (0600). For an
existing local override, `owned` remains its immutable `original_owned` value.
Review source identity, target identity and every original/current/incoming
fingerprint. The explicit approval argument is SHA256 of the complete plan file,
including whitespace. Both arguments are required together and require `--upgrade`:

```bash
bash <trusted-pinned-clone>/.claude/scripts/reconcile-claude-dir.sh \
  --from <trusted-pinned-clone> --into <repo> --state-root <private-directory> \
  --upgrade --resolution-plan <private-plan.json> \
  --approve-plan-sha256 <reviewed-exact-plan-sha256> --dry-run
# After separately approving that exact target transaction, repeat without --dry-run.
```

The transfer preserves current bytes and modes, records original/local/upstream
fingerprints in schema-v2 `local_overrides`, and excludes those paths from managed
writes. Old v1 updaters reject v2 manifests rather than overwriting them. V1
manifests remain readable. Plans are one-shot: the resulting manifest fingerprint
changes, so replaying a consumed plan rejects. Ordinary subsequent upgrades omit
the plan and preserve local owner edits. If upstream changes or removes a reviewed
configuration path, the upgrade blocks until a new exact plan is reviewed. For an
already transferred path only, reviewed upstream absence is represented by JSON
`null`; first-time transfers still require a real incoming source fingerprint.
Reappearance also requires renewed exact review. Repository HEAD/common-directory
identity is fenced again before target effects, each managed write and completion. Missing,
unsafe or symlinked local paths always block. The installer never generates its
own approval, automatically merges configuration, or hand-edits an existing
ownership manifest.

Schema-v2 private journals also fingerprint preserved local paths. A later local
change fences rollback/recovery before target restoration, leaving the pending
journal for operator inspection. Recovery must use this version or a compatible
newer trusted updater. These implementation fixtures do not approve migration of
any live adopter or enable authority, reporting, providers or deployment.

### Whole-bundle updates with a separately trusted updater

Review and bind both the updater checkout SHA and the clean whole-bundle source
SHA selected by `--from`; they can differ. A trusted compatible updater may apply
a separately reviewed older bundle as an intermediate stage. Invoke that trusted
updater explicitly at every stage: an older installed updater must reject a v2
manifest. Do not substitute partial bundles or hand-edit the manifest. Each stage
needs its own exact source/target/manifest proposal and review; a keep-local plan
also binds the incoming configuration fingerprints and its complete approval hash.
Use the same private journal protections, inspect the resulting diff and commit a
verified stage before proposing the next one. These instructions do not approve
any particular live adopter update or assert that a pending revision is on main.
