# Factory activation

The operator authorized preparing the private **qyndex-factory** App for **qyndex**. The bootstrap policy and merge mode are intentionally disabled: an App installation alone cannot authorize merging. The activation PR changes merge/security authority and therefore needs the operator's decision before merging it.

## Account setup

1. Register the private App at [qyndex App registration](https://github.com/organizations/qyndex/settings/apps/new). Use `factory/github-app-manifest.json` for its name, homepage and permissions. Turn webhook delivery off; no callback or webhook service is required for Actions installation tokens. Give it Actions read, Checks write, Contents write, Pull requests write, Administration read. No Administration write, Workflows write or bypass role.
2. Install it on **claude-init only**. Generate a private key in the App settings; keep the key on your machine, never in chat or this repository. The App ID is a non-secret number.
3. Create the **factory-authority** Actions environment, restricted to the **main** deployment branch. Store `FACTORY_APP_ID` as an environment variable and `FACTORY_APP_PRIVATE_KEY` as its encrypted environment secret. Ordinary merge runs need no human environment reviewer: approved default-branch code and the App-pinned ruleset are the authority.
4. Provide the App ID, then populate the approved policy and provision the independent verifier/reviewer workflows. The current policy explicitly reports those missing producers; legacy action success or comments are insufficient substitutes.

[GitHub permission guidance](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/choosing-permissions-for-a-github-app) and [App registration](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app) describe the account steps. The App manifest is a registration configuration, not a credential or a running service.

## Protected policy and proof producers

`factory/policy.json` lives on the protected default branch. Its initial state has `enabled: false` and `merge_enabled: false`, no App ID, no approved specs and no verifier/reviewer runtime hashes. Check producer defaults use the observed GitHub Actions App ID **15368**. Confirm those pins against the actual PR before applying them.

Each approved spec entry supplies its SHA-256, full AC ID set and explicit allowed path prefixes. Candidates use `factory/spec-<id>/<description>` branches. Current implementation accepts one complete approved spec per PR. Bot release/dependency branches have no implicit exemption; registering those scopes is separate authority work. Authority paths, including renamed old paths, cannot merge autonomously. Never use an implementation PR to modify its own approval policy.

Separate protected verifier/reviewer workflow definitions must produce `factory-verification` and `factory-review` artifacts. Each producer entry pins its GitHub workflow ID and SHA-256 digests for all workflow/script/prompt/config files forming its trusted runtime. List those files as protected paths. Both run against the exact candidate head, use fresh isolated execution, and have no factory App key. Review uses a distinct workflow/run; the implementer cannot produce either verdict. A different model alone is insufficient.

Each artifact ZIP contains `evidence.json` and, for observations, `artifacts/<sha256>` byte files. The verifier document contains the binding fields, generation timestamp, acceptance observations and verification verdict. The review document contains identical bindings, its timestamp and review verdict. The coordinator authenticates the run from GitHub, verifies archive and observation digests, checks producer runtime definitions, and substitutes live check receipts for candidate claims. `test/factory-coordinator.sh` and `test/candidate-evidence.sh` contain complete fixtures. Producer actor IDs are `workflow:<id>/run:<id>`.

## Reviewed activation sequence

1. Review and merge the bootstrap PR through the operator route. It cannot self-approve: its authority-path changes are rejected by factory policy. No live ruleset is changed by the PR itself.
2. Populate the App/spec/producer configuration through a separate reviewed authority change. Run preflight and a shadow candidate. Do not substitute fabricated PASS documents to unblock setup.
3. Generate the additive live ruleset with `python3 .claude/scripts/factory-ruleset-plan.py --app-id <id> --output /tmp/factory-ruleset.json`. Review the result. It preserves stricter live review/thread controls, strict status checks and no bypass actors; it adds `factory-eligibility` pinned to the dedicated App and pins existing workflow checks to their producer.
4. Apply that reviewed policy with the operator administration identity. The App has no permission to change it. Disable already-armed native auto-merge requests during cutover and use request-only routes thereafter.
5. Run `Factory Merge Authority` in **shadow** mode for an eligible fixture PR and negative candidates. The default mode never merges. Keep `merge_enabled: false` during shadow testing. Enable merge mode through a reviewed policy revision only after the exact-head shadow proof and the live pin have been verified.
6. Run an ordinary approved candidate through merge mode. Retain its exact returned merge SHA and external `factory-receipt` artifact. Recover a missing receipt from GitHub before retrying an external action.

The coordinator uses GitHub's [conditional head SHA merge](https://docs.github.com/en/rest/pulls/pulls#merge-a-pull-request) and queries [active rules applying to the target branch](https://docs.github.com/en/rest/repos/rules#get-rules-for-a-branch). It rechecks candidate and protection before merging. Default-branch dispatch, repository-wide serialization, pinned actions and no candidate checkout keep privileged code outside the implementation workspace.

## Activation boundaries still pending

This package prepares merge authority; it does not yet close every factory package. Protected evidence producers, durable claims and receipt reconciliation, daily Slack delivery, feedback amendments and complete coverage adapters remain dependencies. The 08:00 Australia/Sydney digest to qyndex / qyndex-alerts has not been installed. No production environment or deployment target exists; autonomous production stays disabled until additional health, release and rollback gates are proven.

A coordinator request is neither a merge receipt nor product acceptance. Rollback must name the recorded merge SHA and go through an approved rollback PR; local integration no longer reverts whichever commit happens to be HEAD or pushes main.

## Implementation verification

All **63 maintained suites passed on macOS and Linux** in disposable checkouts with Git history. The coordinator regression passed 26 assertions, including actual ZIP/digest checks and shadow mode; request-boundary regression passed 10. Structural validation passed 79 checks with one historical no-op acceptance warning and zero failures. TDD ledger passed with historical exemptions still reported; Actionlint expression checks and warning-level ShellCheck for changed scripts passed. Harness Validate now fetches full history so CI can reproduce historical provenance checks.

These are implementation checks; the actual GitHub candidate run, App identity and shadow proof are recorded separately. No live merge/security rule, App installation, Slack schedule or production deployment is changed by local testing.

## Published bootstrap candidate

Draft [PR #50](https://github.com/qyndex/claude-init/pull/50) is isolated on `codex/factory-activation`; the original branch and initiative edits remain intact. Harness Validate passed on initial candidate `633faee68b3a86fe5af9561042e58021b9fd5105` ([run](https://github.com/qyndex/claude-init/actions/runs/37897616485)). Subsequent CI-driven fixes require a new final-head run, recorded in the PR checks. Independent review jobs remain pending while this PR is a draft.

The legacy consumer now checks every touched spec, exact AC counts, successful runner/smoke status and passing tagged results instead of choosing one latest bundle. A captured original-gate regression demonstrates that a zero-AC bundle could previously hide a second missing spec. Bootstrap reports come from actual shell acceptance commands and the existing collector's smoke reruns. They explicitly record that they are local implementation evidence; final factory authority still requires authenticated external artifacts. Silent-failure lint annotations explain OS-parser probes and diagnostic assertions, while actual parse and mediation failures now surface explicitly. Coverage thresholds cannot be lowered through candidate environment variables.

Completed candidate check/verdict workflows re-request evaluation, so a request issued before CI finishes does not require a manual retry. Repository-wide serialization still evaluates the latest exact head. Shadow readiness and actual merge enablement are separate policy switches; changing either policy revision invalidates old evidence and requires fresh producer runs.

Independent producer jobs must report unique required contexts `factory-verification` and `factory-independent-review`, failing the job when the machine verdict fails. The reviewed ruleset planner adds both contexts pinned to GitHub Actions, alongside App-pinned eligibility. Failed merge evaluations publish a new failure check rather than leaving an earlier eligibility success as the latest check. API failure remains a hard failure.
