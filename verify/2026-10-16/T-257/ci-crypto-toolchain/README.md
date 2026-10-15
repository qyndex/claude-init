# Evidence workflow crypto toolchain

The actual evidence-gate workflow lacked the pinned crypto install already used by harness-validate, despite re-executing encrypted intake acceptance. The new regression parses actual workflow jobs and steps, requires the exact pinned manifest command before G49 verification under the same condition without continue-on-error, and checks the maintained harness uses the same command and all manifest dependencies are exact-pinned.

An initial test parser attempt failed on an unrelated shell continuation (ValueError: No escaped character); the parser now treats unparseable individual shell lines as nonmatching commands. Before the workflow edit, the corrected test failed specifically because the required dependency install was absent (red.log). Adding the single install command made the identical test pass (green.log). Actionlint, shell syntax, and diff checks passed.

No dependencies were downloaded locally, no production policy or gate limits changed, and no clean GitHub runner or full aggregate is claimed by this focused regression. Owner final CI remains required.
