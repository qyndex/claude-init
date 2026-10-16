# T335 approved reporting-App workflow test closure

Two old substring assertions treated the App action input
permission-administration: read as a native workflow Administration grant.
Actual publication aggregate failed in factory-workflow-baseline; after that
focused correction the next actual terminal assertion was the identical check in
factory-policy-approval. Both genuine focused baseline failures are retained.
Slack receipt mismatch diagnostics earlier in aggregate stderr are intentional
negative cases, not the terminal failure.

Both tests now use existing PyYAML safe_load to inspect native workflow/job
permissions mappings separately from step.with App permission inputs. Native
Administration/OIDC block and inline grants still reject; App Administration
read passes and write rejects. Meaningful mutated workflow/job cases preserve the
guard, rather than removing it. Existing policy approval/GET-only credentials,
queue serialization, actual protected shell ingress and actionlint remain.

The initial anchored-block implementation passed its focused cases and an
intermediate aggregate, but root review caught its lost inline-native denial.
Actual new inline assertions went RED on that regex. Final fixtures use valid
inline mapping replacements; the parser repair passes them. Intermediate raw
results remain labelled, not substituted for final proof. The final existing
Spec029 aggregate ran once on final YAML-aware bytes: exit0 in19.74 seconds,
original300-second bound, pinned Python and available own-process inspection.
Its own output explicitly leaves fullAC8 live acceptance pending.

Only the two test files and the sanctioned T335 files union changed; no original
task, production helper, workflow, permission, policy, setting or limit changed.
PyYAML is an existing harness/CI dependency, not a newly installed package. No
T290, T288 fifteen-suite, producer or1001-history rerun was performed.
