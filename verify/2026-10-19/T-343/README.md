# T-343 local smoke isolation proof

Base source: 69574d23988d1a98c2c6f6f27c08815449a59351. Approved Spec003 AC21/T131 preservation continuation; no policy, workflow, credential or authority change.

`red.log` is a genuine failure of the new regression against unchanged production collector code: collector A retained collector B's smoke marker. The test used two distinct temporary Git repositories and their actual copied collectors. Each verifier emitted a synthetic marker; A paused after emission while B completed, then A resumed. The historical global scratch file, if present, was backed up privately and restored without reading its content into output.

`green.log` passes both deterministic interleavings (A17/B0 and A0/B23), covering four independently generated bundles. Assertions verify each bundle's own marker, exclusion of the other marker, own smoke exit and verdict, runner exit, AC count and retained raw AC proof. Production change moves scratch output into the already unique attempt directory; the full smoke output stays available there and existing `smoke.log` still retains its bounded tail and exit summary. Synthetic verifier output is not actual application or native CI acceptance.

Additional completed local checks: proof preservation21/21, evidence finalization5/5, acceptance parser9/9, ShellCheck warning-level clean. Exact logs are adjacent. No gate skip was used. Full Spec003 collector, full harness smoke, native independent factory evidence, PR publication and merge have not run for this repair. The parent will independently review and prepare publication. No GitHub action, protected state/log read, credential operation or deployment occurred.

This change does not serialize collectors writing the same canonical output directory. Its scope is isolation between distinct collection attempts/repositories, not a broader output locking redesign. Full retained smoke output can contain ordinary test paths/timestamps and must be reviewed before public proof upload.

## Subsequent parent verification

The full unskipped Spec003 collector ran after the implementation commit: full smoke PASS(exit0), whole-spec FAIL0/21 because no complete tagged acceptance result was supplied. This supersedes the earlier not-run observation above; no whole-spec or native credit is claimed. Actual tool-free Sonnet5.5 source review found no blocker, with complete nits/adjudication retained. Full raw scratch is not selected for public upload.
