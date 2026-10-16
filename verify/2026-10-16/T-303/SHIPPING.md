# T303 local shipping verification

Root independently reran the 27 diagnostic acceptance cases. Fresh shell
subprocesses then recorded seven actual command outputs/hashes against source
2f3defe500687d62b1db9b50ad118c6380c06c5f. The Spec010 results map all five
criteria to those commands, including the new rejection diagnostics. These are
local fixtures, not native attestations or an actual protected App comparison.

The first collector's actual smoke failed because the disposable local-source
clone lacked origin/main; its full output is retained. Fetching actual protected
main6a004 supplied the required base. No source change or gate waiver was used.
The rerun collector passed5/5 with smoke0; actual full smoke and collector logs
are retained. Original behavioral and queued-frontier RED artifacts remain intact.

Full candidate-reachable history Gitleaks scanned149commits without findings.
Source commitlint/trailers passed. Independent retained model review and final-head
GitHub checks are separate publication steps; neither is claimed by this file.

Protected App run38833564091 failed observation metadata comparison. The saved
operator observation still matches an actual operator GET, but the App component
mismatch is unknown. This repair preserves strict enforcement and prepares only
a bounded failure audit. Actual deployed App diagnostics remain required. Shadow
authority and merge mode are off. No policy protection, secret or permission was
changed; all twelve strict App-pinned contexts remain required. A new, concrete
maintenance approval is required before landing this authority-source repair.
