# Configure an adopted factory harness

Installation distributes immutable process scripts, pinned encryption requirements and disabled neutral examples. Review and commit the resulting files. Each repository supplies its own approved specifications, tasks, protected policies, GitHub App installation, Slack identity, private runtime storage and deployment adapter. Examples are references, not enabled profiles. The distribution repository's pilot is a separate installation.

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

Reporting and feedback are optional. Supply this repository's own Slack team/channel, operator allowlist, intake boundary, state branch and exact bootstrap receipt. Provision secrets in main-only environments and independently validate branch/environment policy before activation. Public state may hold only approved public report facts and encrypted feedback; ciphertext size and update timing remain public. Never store tokens, keys or plaintext feedback in Git. See FACTORY-FEEDBACK.md.

The installer omits source pilot policy, App manifest, live workflows and private state. Apply separately reviewed per-repository workflows, protection and authority definitions. Real native subscription auth/capacity, independent reviewer proof and shadow delivery remain required rollout gates. The existing subscription has no metered fallback. Installation does not certify production: each adopting service must configure and prove its deployment, SLO and rollback adapter before enabling autonomous releases.


For a separately reviewed authority setup, run `python3 .claude/scripts/factory-ruleset-plan.py --policy <protected-policy.json> --ruleset-id <this-branch-active-id> --app-id <this-installation-app-id> --output <proposal.json>`. The policy supplies this repository/base branch and its complete check producer map. Review the generated proposal before applying anything; the tool never enables workflows, changes rules or merges candidates.
