# Repeat independent review disposition

Actual Sonnet5.5 reviewed frozen d735e07 versus protected main9183908, completed successfully with changes requested. This is local static independent review, not native factory attestation or merge authority.

Guard HIGH here-string and executable-heredoc/suffix regressions are confirmed against actual hook/current main using JSON data only. T129 is reopened; no supplied command was executed.

T130 false tooling classifications are confirmed using actual failing Python unittest and Node assertion helpers, compared with main's ledger writer. T130 is reopened; startup detection and genuine assertion evidence both need preservation.

The rule-ID ambiguity compatibility LOW is retained as a supported-profile limitation rather than a required change: the gate deliberately supports only unambiguous inline-ID fallback when no index is supplied; OASIS SARIF2.1.0 sections3.52.3/3.52.4 describe descriptor lookup and state that IDs do not participate in lookup. No exact-ID-precedence rule is asserted by that text. Ambiguous metadata fails closed; indexed descriptor selection remains available.

A separate primary-source check found unequal explicitly supplied ruleIndex/rule.index must reject before -1 normalization (OASIS3.27.6 and3.52.5); its actual reproduction is retained for T326 followup.

Analysis/task counts and spec lifecycle must be regenerated after final integration. Historical AC proof is not re-certified; source remains unpublished and review changes are unresolved.

Primary: https://docs.oasis-open.org/sarif/sarif/v2.1.0/os/sarif-v2.1.0-os.html
