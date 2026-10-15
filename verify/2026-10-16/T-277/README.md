# T-277 real Git source equivalence regression

This is a test-only task. The first actual run passed on unchanged T-276 production source `9d46d0dbd98312fd92817f2103ba09069e612071`; `current-first-pass.txt` retains that observation. No current missing behavior or production fix is claimed.

Nine cases use an actual temporary Git repository: two distinct ordinary source SHAs with the same approved exact policy/runtime authenticate without changing the external profile or adding any revision imports; changes to each of six emitter dependencies and to policy fail. Every source fetch asserts immutable run HEAD and rejects using the PR candidate SHA. The existing API fixture supplies archive/PR behavior; the test does not duplicate authentication logic.

The repository has no test-only exemption from its required red/green files. Per explicit review instruction, `red.log` is a real historical pre-T276 baseline run at exact source `c871ae5e4648451976cbdf0fe4030826e70d3ad2`, using the identical new regression script copied into a disposable checkout. It fails because the external-profile API was absent. Its command/source/test digest are recorded. This is a historical API regression failure, not a newly discovered current failure, and the ledger's generic assertion-failure label does not change that fact. Current GREEN was rerun afterwards and passed. No production code was modified merely to generate RED.

Additional current checks: 24 immutable-source cases, 33 strict parser cases and existing receipt projection AC-1–4 passed; structural validation passed with four existing warnings. No live profile, hosted receipt, archive durability, revocation integration or complete unattended readiness is claimed. T-278 and later tasks remain pending.
