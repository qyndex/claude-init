# Actual-base bootstrap publication attempt

Collector009 ran at d965ac0 against actual protected base b533a82 without skip flags. It failed: T287 exceeded the unchanged300-second acceptance limit after approximately375/1001actual retained appends. Later task acceptances did not execute. AC-tagged stack proof was absent, so no AC/native readiness PASS is claimed. Canonical generated009evidence/body retains the FAIL.

The raw full smoke and collector logs remain preserved locally in /private/tmp/factory-evidence-pre-bootstrap-20261017/failed-bootstrap009; the compact result binds the smoke SHA256. They are not implied to be public repository artifacts. Existing earlier T179/T318 acceptance failures remain preserved separately. T287 is reopened until its actual bounded acceptance passes. Source/native bootstrap and full remaining publication gates are incomplete.
