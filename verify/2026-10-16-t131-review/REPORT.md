# T131 independent-review integrity followup

Actual Sonnet5.5 review at045f9c0 assessed the original snapshot/consumer preservation positively and flagged checkout-local Python import shadowing in the integrity path. Genuine RED demonstrates controlled json.py/hashlib.py modules executing from the fixture root and preventing validation. The same21-case suite passes after all three integrity Python invocations use isolated mode (-I), preserving19 original cases plus2 new import controls. No normal runner command is isolated or changed; no caller hooks or security settings are disabled.

RED began before local midnight on2026-10-16; that real failure is retained separately. The command was rerun genuinely RED on2026-10-17 before the repair, then GREEN on that date. Original T131 RED/GREEN remain intact.

The review's TOCTOU concern is a limitation of local bootstrap evidence, not a claim of independent authority. The current consumer revalidates JSON/AC results but does not use results_sha256 as authenticated authority. Checkpoint hashing detects the tested synchronous smoke mutations and identifies observed bytes; it does not freeze a filesystem against arbitrary same-user background writers. The protected independent producer separately reruns checks. No filesystem-isolation or immutable-local-proof claim is made. Supporting concurrent adversarial writers would require a separately specified trust boundary, rather than pretending a local checksum supplies it.

The midnight/global Git fixture observations are portability limitations, not evidence that those configurations ran here. Actual local fixture/consumer commands passed with the current configuration. No hook/signing bypass is introduced to silence hypothetical environments.
