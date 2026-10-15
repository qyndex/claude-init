# T-254 upgrade ownership characterization

The new actual CLI `upgrade` selector passed its first execution. Only the test changed; factory-adopt.py required no production fix. The adjacent characterization marker uses check-tdd-ledger.sh's documented green-only exemption. No RED phase is fabricated.

The fixture starts with clean source A assembled from current tracked package bytes and explicit task files, adopts it into a fresh product Git repository through the real CLI, and commits an isolated source revision B. B changes the disabled template's finite limit, guide bytes, Scout script bytes and executable mode. Actual CLI acceptance checks require the explicit upgrade flag, bind the B SHA, verify exact target bytes/hashes/modes and unchanged neutral policy, then replay idempotently without another journal. Source commits and all fixture paths remain temporary.

Foreign intake template and guide collisions reject both initial and --upgrade adoption. A separately freshly adopted A target with a local formerly managed Scout customization rejects the B upgrade. Complete before/after inventories include file bytes, modes and directories, manifest and external journal contents; conflicts leave all unchanged. Target tasks/memory/settings/state and a separate private disabled policy remain exact. Source private/pilot sentinels stay excluded, hooks remain unregistered, and no provider, network, cloud or OS-account registry bootstrap occurs. Every actual CLI subprocess uses the existing read-only-local-Git/network audit.

manifest.tsv records six checks, all exit 0. The existing adoption regression ran once; package compatibility also passed. Homebrew Python 3.14.4 is selected only on the scoped adoption commands. Structural validation retains four existing warnings. The ledger helper generically warns about no RED and no timeout/gtimeout; characterization is an explicit repository-gate exemption, and each actual CLI invocation has its own 60-second timeout.

No commit or task status changed. This is offline ownership verification, not a live capability or adopter activation certificate. T-255 matrix and T-256 rollback were not implemented in this task.
