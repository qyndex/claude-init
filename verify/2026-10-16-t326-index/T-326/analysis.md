# T326 AC5 corrective analysis before source

Approved Spec006 AC5 requires agreement of driver rule identity indexes, with malformed metadata rejected. Approved plan calls for inconsistent identities to fail closed; T326 acceptance invokes the production SARIF gate. This narrow followup compares both explicit index fields before interpreting -1 as absent. No new scope, dependency, OQ or cycle is introduced. T326 remains the existing task and its independent prerequisites are empty. Prior analysis counts were 11/12 done; this review does not recertify historical acceptance criteria.

Parent supplied actual reproduction cites OASIS SARIF 2.1.0 sections 3.27.6/3.52.5: both present fields SHALL equal. Sole sentinel or both equal sentinel remain permitted. Exact-ID fallback profile, scanner dispositions, T329 trust policy and runner source identity are unchanged. No live policy activation.
