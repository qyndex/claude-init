# Large host Python fixture correction

The bundled Python executable is 18,058,560 bytes. Before the fixture correction, the actual hooks command failed while loading the intake source contract at its unchanged 8,000,000-byte source limit. The fixtures redundantly treated the host testing Python as an intake source artifact. The configured guarded interpreter is the private wrapper; that wrapper remains pinned. The redundant host Python entry is removed from both source and probe collections. No production behavior or bounds changed.

The worker-contract regression separately validates a designated interpreter larger than 8 MB through the existing protected executable pin chain, rejects ordinary source reading of that interpreter, and rejects byte and profile-hash drift. This is offline fixture evidence, not a live interpreter capability certificate.

The initial launch attempt failed because the filesystem sandbox denied /bin/ps process inspection; its log is retained. The authorized launch rerun passed all 13 cases. The identical hooks command passed all 7 cases after the fixture correction. Descriptor and worker-contract suites also passed. See manifest.tsv for exact exit outcomes. No complete local-all or phase3 suite was rerun by this agent; the owner will run the final aggregate and evidence gates.
