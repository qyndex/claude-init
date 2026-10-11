# Deploy integration — bring your own target

Production is disabled in the shipped harness. The canary workflow refuses every dispatch, including `DEPLOY_WIRED=true`. A variable cannot prove that a platform deployed an artifact. The stub has no deployment-write permission and emits no GitHub deployment success.

This document specifies the required adopter contract. The protected reusable release core is `.claude/scripts/factory-release.py`. Its isolated real HTTP rollout/rollback drills exercise the generic contract; they do not certify any future production target. Every adopter owns its platform, service, credentials and durable release state. The harness repository needs no pretend production service.

## Protected release inputs

Before enabling a replacement workflow, configure these outside implementation-agent control:

- Repository, service and environment identity; explicit approved specs eligible for that service.
- Trusted coordinator policy and authenticated delivery for the actual merged SHA, including independent review and acceptance provenance. A green arbitrary CI run, caller-supplied proof file or PR body is insufficient.
- Canonical pinned adapter executable and scripts, immutable artifact digest, approved provider operations and dedicated deployment secret references. Recheck hashes around execution; bound subprocess output and time.
- Progressive traffic stages ending at 100%, an approved known-good baseline SHA, service-bound health endpoint, sample floor, observation window, freshness bound, error-rate and latency SLO thresholds.
- Private durable state isolated from candidates, repository/service/environment binding, exclusive release ownership and a recovery owner. An ephemeral Actions checkout plus an end-of-run upload does not establish durability before effects.

Adopters can use their platform's protected durable coordinator or transactional remote backend. GitHub-hosted reporting state does not automatically supply a production transaction boundary. Choose and prove release durability separately; never publish plaintext credentials, raw operator feedback or provider responses to the public reporting branch.

## Adapter operations and evidence

The protected adapter must support deploy, observe, lookup and rollback. Requests bind repository, service, environment, operation ID, merged SHA and traffic stage. Deployment receipts additionally bind the actual provider deployment ID and immutable artifact digest. Lookup must establish the same exact effect after a lost acknowledgement.

Health observations must bind that same service/version/stage and include measured sample/error counts, start/end timestamps and latency. Empty, stale, malformed, identity-mismatched or unavailable metrics block promotion. Observe the approved known-good baseline before any candidate effect, then measure every stage before advancing. A successful command or an HTTP response from an unrelated version does not satisfy the SLO gate.

Deployment credentials belong only to the approved adapter environment. Do not pass GitHub merge App keys, Slack tokens, reviewer credentials or private feedback keys to deployment processes. Candidate source must not supply the adapter, policy or health verdict.

## Durable execution and recovery

1. Authenticate delivery and verify protected policy, adapter pins, baseline and complete configuration before dispatch.
2. Record durable intent and exact idempotency identity before each provider mutation. Serialize unresolved operations for the service/environment.
3. Record the confirmed deployment receipt before measuring the current stage. Require consistent artifact identity across the rollout.
4. On SLO breach, record rollback intent, restore the recorded prior known-good version and verify its actual health before reporting rolled back.
5. On uncertain acknowledgement or controller death, reconcile the recorded effect through lookup. Never blindly repeat deploy or rollback, erase uncertainty or release the fence because a timeout elapsed.
6. Failed or uncertain rollback remains blocked and produces a protected failure outcome for the adopter's GitHub/Slack alert route. Independent monitoring is optional; GitHub-only alerts do not cover a complete GitHub outage.
7. Publish deployment success only after the final measured healthy stage. Keep engineering verification, merge, production release and product acceptance distinct.

## Activation evidence

Run isolated drills against a real local service or staging target: healthy promotion, unhealthy candidate, measured rollback restoration, lost deploy acknowledgement, controller restart, duplicate delivery, unavailable lookup, lost rollback acknowledgement and wrong identity. Demonstrate no duplicate effects and no secret leakage. Fixtures establish the reusable contract only.

Before enabling an adopter's real production target, repeat applicable drills using its actual provider, traffic routing, durable backend, credentials and health measurements. Confirm protected workflow/environment access and record the approved policy hash. Keep production disabled if any adapter, baseline, metrics, provenance or recovery prerequisite is missing. Enable production separately from auto-merge.

Replace the shipped stub with the verified protected pipeline. If issue lifecycle consumes `deployment_status: success`, emit that event only from the final authenticated healthy release receipt; never from placeholder steps or a failed rollback. Retain source-bound receipts and alert links for the morning digest.

## Release core invocation

Provision an owner-only directory (mode 700) on the adopter’s durable controller filesystem, outside any candidate checkout. Keep release configuration and trusted coordinator policy mode 600. Start from the disabled `factory/release.example.json`; configure every field, hash the canonical executable and each absolute script input, and supply approved deployment-only credential references. The baseline must be a genuinely approved known-good version.

Invoke the trusted controller with `python3 .claude/scripts/factory-release.py --config /private/controller/release.json --policy /private/controller/coordinator-policy.json --db /private/controller/release.sqlite --run-id <successful-coordinator-run>`. The CLI authenticates the protected coordinator’s actual GitHub receipt; it has no caller-supplied proof-file or adapter override. Fixture tests inject synthetic delivery into the core API and must never be represented as that authenticated live path.

The private database records intent and confirmed outcomes before subsequent effects. On loss of an acknowledgement, repeat the same authenticated delivery to reconcile the exact operation through adapter lookup. Unknown effects or rollback health retain the service fence; do not reset or delete the database. Terminal repeats return the historical result and do not redeploy it. Protect the durable volume and controller identity separately from implementation workers.

Adapter stdout is exactly one bounded JSON document. Deploy/lookup/rollback receipts have schema_version, repository, service, environment, operation_id, sha, stage, status (present), deployment_id and artifact_digest (SHA-256). Observe has the same identity fields plus metrics: samples, errors, window_start, window_end (Unix timestamps) and p95_latency_ms. Each adapter receives action and canonical request as arguments; secrets are passed only through approved environment mappings. Pin the adapter’s dependencies and platform SDK as part of the protected controller runtime; executable-file hashes alone do not authenticate dynamic imports or remote provider behavior.
