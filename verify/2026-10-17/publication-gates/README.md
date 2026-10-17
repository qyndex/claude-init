# Publication gate observations

The required collectors for 009, 014 and 029 ran against protected base 91839087a769bd45670df5b84cb96993bcb97d42 and source b2fe148. All returned FAIL (smoke exit 1); this candidate must remain draft. Tagged local assertions are not native attestation or live activation proof.

The actual verifier failed at T179 because FACTORY_ACTIVATION_PR was unset. Later task acceptance commands were not executed by these collectors. The T318 command also requires explicit live run/attempt selectors; no implicit selectors or live success are claimed. Prior recorded genuine acceptance remains preserved, without being relabelled as a successful current publication verifier.

The first 009 invocation used /private/tmp/sbxbin, whose Python lacked yaml. Its dependency probe failed before collection, but the shell continued and the actual verifier subsequently failed at T179. The complete observed failed collector output is retained. 014/029 used the established bundled Python with yaml and cryptography. No runtime was installed or test gate disabled.

Candidate history scan: 96 commits, 8.37 MB, zero leaks. Commit trailer check: 96 commits passed. These observations precede this proof-only commit. No credentials, live policies, secrets or authority flags were changed.
