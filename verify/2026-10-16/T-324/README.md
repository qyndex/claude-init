# T-324 — explicit read-only live CLI composition

Actual RED at 14:06:03 Sydney on 2026-10-16 exposed that invoking the helper with
missing/invalid live selectors exited successfully without an observation. The
minimal CLI and explicit shell dispatch followed that failure. A supplemental
actual RED then exposed argparse accepting abbreviated --liv; exact flags now
require allow_abbrev=False. Final GREEN at 14:08:10 passes eleven CLI composition,
35 source-observer and twelve real-Git journal cases.

No-argument shell execution runs offline contract self-tests and prints that live
rollout remains unverified. Only explicit --live dispatches to the real read-only
helper, forwarding mandatory drill/recovery/repeat run IDs and attempts. Missing,
unbounded, abbreviated or unknown selectors, capture files and alternate API
hosts/endpoints cannot supply evidence or trigger fallback to fixtures. Missing
selectors fail before external observation. Actual rollout must supply explicit
safe selectors in its recorded command; they are not baked into the shell.

The live CLI uses the existing protected non-secret q.build_config environment,
then the fixed GitHub adapter and observe_journal. It never constructs a Slack
client or retrieves Slack/state-writer secrets. The existing safe administrative
observation gains only a verification_mode=live-read-only marker and an 8192-byte
output bound. Exceptions produce a fixed no-live-credit error without raw API
logs/private history. Source/role consistency checks remain in the existing
observer; there is no caller proof JSON, arbitrary host or input transport option.

The integration fixture reuses the real Git state setup, creates a fresh clean
checkout of the actual Python runtime and serves its synthetic API responses
through a local fake-gh executable. It runs the actual CLI in fresh processes,
with no Slack/state token present. Positive composition and missing/invalid
selectors, disabled configuration, unavailable log, wrong current main and dirty
source are checked. Temporary synthetic log responses are test-only; production
raw logs are never saved. These simulated --live executions are NOT live rollout
or native attestation evidence, despite exercising that CLI path.

The first sandbox GREEN attempt passed the ten original CLI cases but the
existing source regression hit restricted /bin/ps cleanup inspection. That failure
is retained separately, not misclassified as source success. The final complete
suite passed with process inspection enabled; the parent independently repeated
11+35+12 successfully. No network calls occurred. No live variables, source push,
credentials, settings, T320 parent completion, T321 or T318 credit is included.
The parent's pre-existing plan clarification remains untouched and uncommitted.
