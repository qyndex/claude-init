# Configure an adopted factory harness

Installation distributes immutable process scripts, pinned encryption requirements and disabled neutral examples. Review and commit the resulting files. Each repository supplies its own approved specifications, tasks, protected policies, GitHub App installation, Slack identity, private runtime storage and deployment adapter. Examples are references, not enabled profiles. The distribution repository's pilot is a separate installation.

Read [current source-pilot status](FACTORY-STATUS.md) for completed implementation and remaining rollout observations. Its active merge authority does not activate this adopter.

## Greenfield and brownfield verification

Choose an immutable reviewed harness SHA and keep that checkout outside the target. Use [the transactional quickstart](FACTORY-ADOPTER-QUICKSTART.md) for dry-run, conflict review and installation. Keep each target on its own adoption branch and commit its reviewed application baseline first.

For a greenfield application, initialize its own Git repository and establish the product brief, approved initial specification, selected stack, runnable application, test commands and first meaningful acceptance journey. `/kickoff` helps draft the scope; it does not approve it. A repository with no application or acceptance journey cannot pass application readiness merely because the harness scripts installed successfully.

For a brownfield application, inventory its existing architecture, conventions, instructions, tests, migrations, deployment and known failures before importing a backlog. Use `/adopt start` and preserve the existing source and private state. Review unmanaged/customized-file conflicts rather than overwriting them. Record baseline failures explicitly and prove that adoption does not introduce regressions; an existing failure is not a passing check or automatic waiver.

For either target, retain these repository-specific observations before autonomous enablement:

1. Exact repository identity, reviewed harness SHA, installation manifest and application baseline SHA; dry-run/upgrade conflict and interrupted-install recovery results.
2. Actual stack lint/test/build and acceptance commands with observed exit codes, required tool availability and supported coverage. Missing adapters remain blockers.
3. Protected environments and App installation scope, isolated implementation/verification identities, pinned producer/runtime/policy profiles and signed independent exact-head proof. Verify private-repository capabilities separately.
4. Positive shadow eligibility plus stale-head, failed-check, forged-proof, out-of-scope and recovery negatives. Activate only separately approved paths and tasks.
5. If enabled, a real report receipt and authenticated operator feedback/amendment/delivery cycle in that target's own destination and state store.
6. Before production, the real deployment platform/environment, known-good baseline, service health endpoint/SLO, rollback command and durable deployment/rollback receipts. Keep production disabled until the actual target passes.

The source pilot's twenty-delivery expansion threshold is counted from useful authenticated eligible deliveries, accumulated naturally under approved scope. Fixture runs, replay, repeated no-op changes and operator maintenance merges do not count. A new adopter starts its own evidence history; it does not inherit the pilot's sample. Real target URLs and protected configuration are required to execute this checklist, not inferred from examples.

## Pinned encryption dependencies

Provision an isolated Python environment outside the candidate repository and implementation access. For example, on the trusted controller choose an owner-only private root and run:

```sh
FACTORY_PRIVATE_ROOT="$HOME/.local/state/my-repository-factory"
mkdir -p "$FACTORY_PRIVATE_ROOT"
chmod 700 "$FACTORY_PRIVATE_ROOT"
python3 -m venv "$FACTORY_PRIVATE_ROOT/venv"
"$FACTORY_PRIVATE_ROOT/venv/bin/python" -m pip install -r factory/feedback-crypto-requirements.txt
```

Use that interpreter for encrypted feedback adapters. Dependency provisioning is explicit; the installer never runs pip or candidate setup. Pin the reviewed harness source SHA and dependency requirements. Keep keys, tokens, private SQLite and attempt logs in protected storage outside candidate mounts; file modes do not isolate hostile code running as the same host user. Hosted trusted jobs install the same reviewed requirements in ephemeral environments.

## Per-repository configuration

Copy reviewed example values into protected configuration outside the candidate checkout. Supply repository identity, private database/attempt paths, approved role/model/executable profile and resource contract. Do not enable incomplete examples. Offline container execution requires nonroot Linux, a reviewed immutable clean image and pinned Docker executable; it supplies no provider network access or subscription credentials. See FACTORY-RUNTIME.md.

For an adopter using a GitHub-hosted GHCR image publisher, qualify that repository's
image before selecting it in protected producer configuration. The order is:

1. Review the adopter-specific image contract, publisher workflow and exact source.
2. Separately review its main-only publishing environment, permissions and publishing
   gate; installation alone does not provision or enable them.
3. Perform the approved hosted publication and verify its exact digest and authenticated
   provenance. Verify the required pull visibility (including anonymous pull where the
   adopter's contract requires it) and native image qualification on that exact image.
4. Review and pin the qualified image in the protected producer profile, then run the
   repository-specific native verification and shadow gates before activation.

Use the adopter's reviewed image specification and workflow for concrete commands;
the generic installer does not distribute a universal live GHCR publisher. A local
Docker run, successful build or ordinary CI check is not authenticated hosted image
acceptance. No image publication or adopter activation is implied by this sequence.

Reporting and feedback are optional. Supply this repository's own Slack team/channel, operator allowlist, intake boundary, state branch and exact bootstrap receipt. Provision secrets in main-only environments and independently validate branch/environment policy before activation. Public state may hold only approved public report facts and encrypted feedback; ciphertext size and update timing remain public. Never store tokens, keys or plaintext feedback in Git. See FACTORY-FEEDBACK.md.

The installer omits source pilot policy, App manifest, live workflows and private state. Apply separately reviewed per-repository workflows, protection and authority definitions. Real native subscription auth/capacity, independent reviewer proof and shadow delivery remain required rollout gates. The existing subscription has no metered fallback. Installation does not certify production: each adopting service must configure and prove its deployment, SLO and rollback adapter before enabling autonomous releases.


For a separately reviewed authority setup, run `python3 .claude/scripts/factory-ruleset-plan.py --policy <protected-policy.json> --ruleset-id <this-branch-active-id> --app-id <this-installation-app-id> --output <proposal.json>`. The policy supplies this repository/base branch and its complete check producer map. Review the generated proposal before applying anything; the tool never enables workflows, changes rules or merges candidates.

## Signed autonomous proof capability

Protected producer proofs use the operator-selected GitHub-native attestation backend. Public repositories support this capability on current GitHub plans; private/internal repositories require GitHub Enterprise Cloud. Confirm that capability before activating autonomous merge authority; unsupported adopters remain blocked rather than accepting unsigned evidence. This prerequisite does not prevent installing the harness or using its other development workflows. See [GitHub's repository-plan requirements](https://docs.github.com/en/enterprise-cloud%40latest/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations).

Use each adopter's own reviewed producer workflows, `id-token: write` and `attestations: write` permission decision, complete runtime source pins, approved spec and genuine signed verifier/reviewer evidence. A public source pilot is not an adopter's certification. Exact certificate identity, protected source/ref/repository, hosted runner and run/attempt must pass independently; no unsigned fallback is provided. ADR0006 records this trust boundary. Production adapters and merge-mode approval remain separate gates.

Enterprise Cloud attestation capability is necessary, not a complete private-repository activation certificate. Private adopters must also configure and prove secure private-candidate retrieval, native provider execution, independent signed evidence and the full repository-specific shadow gates. The public pilot does not certify private operation; this pin refresh does not implement a private-fetch adapter.

### Policy-observation source completeness

Adopters must install the policy-observation helper along with the complete
protected producer runtime (eight files per role) and seven-file receipt emitter
closure. A copied seven-file producer policy is incomplete and must fail preflight.
Follow the main-only environment observation setup in
[FACTORY-ACTIVATION.md](FACTORY-ACTIVATION.md#exact-administrative-observations-for-omitted-bypass-metadata).
The dedicated App retains Administration read. Explicitly visible nonempty or
malformed bypass actors reject even when an observation is configured. Reobserve
exact settled metadata after every policy change; candidate messages cannot grant
this administrative trust. The separate bounded administrative audit expires after
90days and is not native attestation or a live delivery guarantee. Private-repository
capability and secure candidate retrieval must still be established per adopter.

## Queue monitor setup and readiness

The queue monitor is optional and defaults off. The qyndex/claude-init bounded
pilot passed actual live acceptance on 2026-10-16; the
[activation record](activation/2026-10-16-queue-probe/README.md) binds its source and runs.
Every adopter must still review and verify its own rollout. An installation of this harness
is not another repository's Slack/reporting activation. Preserve normal reporting
and feedback while configuring this separate role; do not disable their existing
gates merely to stage the queue workflow.

GitHub [environment-level variables](https://docs.github.com/en/actions/reference/workflows-and-actions/variables)
are available only after the job starts. The three job-if gates therefore need
**repository or organization** variables, preferably explicit per-repository
values: FACTORY_REPORTING_ENABLED (retain existing reporting policy),
FACTORY_REPORTING_PROFILE=github-hosted, and FACTORY_REPORTING_QUEUE_ENABLED=false
until reviewed activation. Do not rely on environment-level copies overriding
job-if evaluation, or create conflicting copies. The CLI also validates the
step's effective values and fails closed if disabled.

Keep identity/storage variables in the main-only factory-reporting environment:

| Variable | Required value |
| --- | --- |
| FACTORY_REPORTING_CHANNEL | This repository's existing Slack channel ID |
| FACTORY_REPORTING_TEAM_ID | Its existing Slack team ID |
| FACTORY_REPORTING_START | Exact established worker reporting origin; never a reset date |
| FACTORY_REPORTING_ATTACHMENTS_ENABLED | Explicit true or false matching the worker policy |
| FACTORY_REPORTING_STATE_REPOSITORY | Exact owner/repository, same as the source repository |
| FACTORY_REPORTING_STATE_BRANCH | Existing protected inert reporting state branch, not default branch |
| FACTORY_REPORTING_POLICY_APPROVALS | Existing reviewed exact policy observations JSON; explicit {} if not required |
| FACTORY_REPORTING_QUEUE_GRACE_MINUTES | Explicit integer string 15–1440; choose 60 initially |
| FACTORY_REPORTING_QUEUE_BOOTSTRAP_SHA | Separately reviewed exact current state commit before first queue role creation |
| FACTORY_REPORTING_QUEUE_INITIALIZE | Explicit true only for that reviewed creation; false afterward |

GITHUB_REPOSITORY and the actual default branch are supplied by the protected
Actions context; FACTORY_REPORTING_BRANCH is derived from that branch by the
workflow. Missing/invalid flags never enable defaults. The queue bootstrap is
separate from the original worker FACTORY_REPORTING_BOOTSTRAP_SHA; it does not
reset digest, feedback or existing queue state. The existing state branch must
already satisfy the backend's inert README/reports and rewrite/deletion guards.

Retain existing FACTORY_SLACK_BOT_TOKEN and FACTORY_REPORTING_STATE_TOKEN secrets
in that same protected environment. No new secret or App permission is needed.
The existing bot must be installed/in the channel with chat-write and appropriate
history access; explicitly enabled files reuse its existing file scopes. Do not
expand the state writer's permissions for Actions: the workflow routes fixed
same-repository Actions GET through github.token/actions:read, and state operations
through the existing writer/fallback. Do not copy bot or writer secrets to a local
checker. Public state holds queue IDs/status/opaque receipts, never plaintext
feedback; unrelated report/encrypted-feedback blobs remain opaque.

After normal source review and checks, review exact configuration and state SHA
before enabling the queue gate. Set initialization true only for that reviewed
first creation, then false once the role exists. If a concurrent worker advances
the branch first, initialization blocks: fresh-read and review a new exact SHA,
never silently repin or reset. Keep workers operational; the new role uses
base_tree/nonforce CAS with at most three retries and does not replace their data.
If the role later disappears, stop and investigate; never delete its journal,
change destination, or reinitialize to clear uncertainty.

Run a labelled manual verification_drill=true on the default branch. The workflow
must complete two fresh CLI invocations in the same run/attempt (one new notice,
then zero). Stop on first failure; do not manually resend an uncertain effect.
Restore bot membership/scopes/history or exact file access and reconcile the
original intent. Deleted/altered/ambiguous history remains blocked; a separately
reviewed migration may be required. Never edit a row to confirmed or remove it.
A normal manual invocation must then show verified recovery, and another zero
new notices. Refresh stalled-run/worker-health observations before this window;
no concurrent production worker is stalled/cancelled as a test.

From a fresh clean reviewed default-branch checkout, the read-only checker can use
the same non-secret configuration via environment plus an existing gh session
able to read source, Actions logs and state protections. For local checking set
GITHUB_REPOSITORY and FACTORY_REPORTING_BRANCH to that actual repository/default
branch. No Slack or state-writer token is required locally. Supply actual IDs and
attempts from the completed protected runs; for example, replace every placeholder:

```sh
bash .claude/scripts/test/factory-reporting-queue-live-evidence.sh --live \
  --drill-run DRILL_RUN_ID --drill-attempt DRILL_ATTEMPT \
  --recovery-run RECOVERY_RUN_ID --recovery-attempt RECOVERY_ATTEMPT \
  --repeat-run REPEAT_RUN_ID --repeat-attempt REPEAT_ATTEMPT
```

Missing selectors never fall back to fixtures. All three runs must share the
clean current reviewed default-branch source, with ordered nonoverlapping windows.
The isolated pilot checker requires one confirmed drill/recovery pair and bounded
history (24 commits/1024 tree entries); extra effects or missing history block.
Do not delete retained records to meet these limits. It checks actual queue-path
publication parent/tree deltas, permitting unrelated worker updates between them.
Its safe output is administrative correlation of protected execution and state,
not native attestation or independent local Slack readback. Keep actual selectors,
source hashes and this limitation in the rollout record; never save raw job logs
or private Slack/feedback history.

`bash .claude/scripts/test/factory-reporting-queue.sh` is the local aggregate.
No-argument live-evidence script execution is offline self-tests only and cannot
complete T318. T321/T317 local evidence and reviewed live activation are separate;
the latter passed for the recorded qyndex/claude-init bounded pilot and remains
required independently for each adopter. Shared environment approvals, Actions-wide failures, delayed
cron runs and Slack outages remain limitations. Healthchecks is disabled and
independent monitoring remains optional. The operator-disabled Issue lifecycle,
Lighthouse CI and E2E on Preview Deploy workflows stay disabled; the factory plan
continues, and those workflows supply no current verification credit.

## Audited receipt readiness before cutover

Use the read-only reporting preflight described in FACTORY-DIGEST.md after the
existing protected bootstrap/profile/store contracts are provisioned and reviewed.
Keep App writer selection and merge authority OFF until their separate concrete
cutover is approved. A local fixture PASS, stored App ID, key-present declaration
or copied profile cannot certify an installed App or a private repository.

The protected-origin check binds actual repository ID/name/privacy, nondefault
state branch, bootstrap commit/tree, audited coverage origin, dedicated reporting
writer and current protections. Positive hidden-actor observations use the
existing exact protected schema2 sidecar; missing observations never become
empty actors or a permissive fallback. Private source requires the actual approved
private store; the public pilot proves no private-adopter access. Public state
may contain only approved public delivery facts and opaque encrypted feedback;
ciphertext size/update timing remain visible.

Before live activation, retain a separately reviewed main-only probe of installed
repository access and observed App permissions, actual protected-origin and
requested retained interval results, plus actual hosted cadence/quota evidence.
If installation metadata is unavailable, report it unverified rather than adding
a privileged token or writing policy/source as a probe. The existing reporting App
uses Contents write, Administration read and Metadata read; do not reuse the merge
key. Missing source history remains an explicit coverage gap. Do not reset an
origin or prune proof to obtain a passing readiness report.

`factory-preflight.py` is part of the current emitter runtime profile closure.
After changing it, review and approve the final exact runtime fingerprints and
policy digest before using that source for new receipt authentication. The
profile does not pin itself or its enclosing commit. Reporting-only dependencies
load only in the explicit reporting mode; the legacy merge preflight execution
imports remain unchanged. Readiness inspection grants neither merge authority
nor production release or product acceptance.
