# T289 reporting readiness evidence

Baseline34f3f422c10cade29193787c4caf87a74b6cbf3a; final source/test hashes in
manifest.json. Canonical red.log is actual assertion failure before implementation;
green.log is actual final acceptance exit0. The exact executing shell/source were
frozen for each run. Supplemental selector/profile REDs retain actual assertions;
initial-focused.log is an intermediate passing real-Git run before the stricter
CLI/profile regressions, not the final acceptance. An earlier diagnostic run
failed when the local Git adapter threw CalledProcessError for a nonexistent SHA;
that is not asserted as product RED or GREEN. The replacement wrong-campaign
negative uses existing authenticated Git history and actual validator rejection.

Tests reuse the existing disposable Git protected origin, receipt publication,
staging, backfill and coverage setup with exact splice assertions. Actual expired
artifacts reconstruct from retained proof; a separately active current profile
coexists with revoked historical proof, whose trust stays withdrawn. Zero active
profiles, foreign source, wrong campaign, private/identity mismatch and mutable
trust race fail; readiness calls assert GET-only state and unchanged Git ref.
CLI tests retain legacy --policy output and reject App OFF, malformed flag,
foreign selection, unavailable fixed config and partial interval selectors.
Neither a caller boolean nor copied SQLite grants proof.

The manual semantic review checked approved Spec014 AC1/2/5–8, declared T289 files,
phase/dependency clearance, legacy compatibility, and no new authority/live scope.
It found no blockers before source work. The structural analyze generator output
is retained as analyze-structural.json: it lacks the required verdict key. That
marker mismatch was discovered after the initial source edit; the skill-format
manual PASS marker was written at the actual later timestamp, not backdated.
No generator behavior was changed. Dependency task closure/proof was copied from
parent's actual canonical acceptance under lock; it is not a rerun of T288.

validation.log retains actual exit0 with four existing warnings. Compile,
ShellCheck, diff-check and source Gitleaks returned0. silent.log is actual exit0
399 within existing459 baseline, not a claim of zero repository suppressions.
Changed-source Semgrep was not run: no confirmed pinned local rules bundle was
available; no mutable registry was fetched. Independent Sonnet review is parent
owned and must bind the exact manifest hashes; this proof does not assert its
pending verdict. No whole-repository security-clean claim or native App/private
access, cadence, operator cutover, delivery, task-credit or merge claim is made.
Merge authority, App selection and Healthchecks settings were not changed.
