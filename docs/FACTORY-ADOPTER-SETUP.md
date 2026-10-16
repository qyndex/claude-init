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
