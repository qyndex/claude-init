# T326 explicit SARIF index agreement

The prior sentinel compatibility repair normalized each -1 before comparing indexes. Thus two contradictory explicit fields (-1/0 or 0/-1) could resolve a warning rule and return clean. OASIS SARIF 2.1.0 sections 3.27.6 and 3.52.5 require both explicit fields to agree. This repair checks their raw equality first; existing numeric/integer validation and sentinel resolution then remain unchanged.

Canonical RED uses both actual production-gate warning-rule reproductions and fails for the expected erroneous clean verdicts. GREEN passes 92 cases: the existing 88 cases, with the two incorrect mixed-sentinel expectations corrected, plus equal -1/-1 and 0/0 warning/error inheritance controls. Sole -1 fallback, booleans, strings, fractions and unsupported metadata retain existing behavior. T329 exact-source audit-policy regressions pass 53/0. Explicit-ID ambiguity policy is unchanged.

The frozen actual post-T328 raw report still rejects exactly two high/critical findings in default mode. A local simulated protected-hash argument accepts exactly two source-bound audit exceptions and explicitly reports NOT a clean security scan. A controlled numeric9 derivative remains blocked. Raw bytes and both registered runner source hashes are unchanged. No live policy, environment, variable, permission or scanner disposition was changed. Local simulation is not protected configuration approval.

Prior T326 red/green evidence is retained under prior-diagnostic, and source/reproduction/control records accompany this report. Independent review and integration remain pending. No timeout/gtimeout is installed on this Mac; ledger commands reported that limitation and completed normally.

Final local checks: ShellCheck and diff checks passed. Full ledger exited 0 with 0 failures/0 warnings and 70 legacy-incomplete records; structural validation exited 0 with 4 existing warnings.
