# Exact immutable ancestry comparison cache

Base source: `600e9ff36e4309a213c067f0d02ae31e6b1d2cc9`. The actual saved-1001 public tail exhausted its shared 2,048-call bound before delivery. Its finite final-tail reproduction measured 276 comparison GETs for 53 exact SHA pairs (223 redundant requests), with all five protected projection SQL tables containing 1,001 rows. This cache does not grant coverage or task credit.

The focused RED actually failed the first repeated-comparison assertion against unchanged production source. A later, unexecuted branch-selector control was corrected to expect the existing route rejection before the GREEN run. No earlier test failure was relabelled.

Only same-repository GET, no payload/raw, exact lowercase SHA pairs and the literal `?per_page=1&page=2` selector reuse the existing invocation-only immutable cache. Every route is validated before a hit. Canonical bytes share the existing cache bound; callers receive decoded copies. Different query order/page, branch selectors, mutable references, repository/protection/source observations and batch reads retain their previous behavior.

Repository-wide caller inspection found this exact query only in `factory-receipt-archive.py::_origin_ancestor`: it validates immutable commit graph identity/status/count fields, not verification annotations. Full tree/publication/current mutable checks remain required independently.

Focused GREEN and the existing 53-case subprocess transport regression passed offline. The large final-tail capacity experiment must run against this committed source separately; these local tests do not establish delivery, native quota readiness, activation, or timely daily reporting.
