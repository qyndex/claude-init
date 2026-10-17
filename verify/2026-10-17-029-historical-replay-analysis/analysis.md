# Semantic analysis — Spec029 approved historical replay amendment

Scope: approved2026-10-17 amendment and existing Spec029/Spec014 boundaries.

AC1–4: existing T203/reporting alert implementation; AC5: T314; AC6: T312/T313; AC7: T315; AC8: T316/T317 and original native T318; AC9: T336–T339 supporting T318 publication acceptance repair.

Plan stages map one-to-one to T336 contract/authentication, T337 protected producer/state retention, T338 read-only replay/authority exclusions, T339 genuine bootstrap. Dependency chain336→337→338→339 has no backward dependency on T318, so it does not create a bootstrap cycle. T318 publication closure is deferred as necessary until real authenticated proof exists; original observations remain historical.

All new tasks reference spec029, use executable shell/Python acceptance syntax, and own only amendment-authorized paths. No new service, package, signing backend or host is added. Existing native signing, bounded process and protected state/CAS facilities are reused. Unknown source, unavailable native proof, unsupported private backend, signature/revocation mismatch and credential absence fail closed. No open product decision remains for this amendment; live trusted-source registration, exact-head merges and upload approval remain separately gated.

Current live checker and delivery/task authority exclusion are explicit compatibility tests. Current-source activation remains T180; adopter delivery remains T222. Existing failed collectors are not upgraded by this analysis.

Verdict: PASS for implementation consistency. Native bootstrap and full publication verification remain unproven.
