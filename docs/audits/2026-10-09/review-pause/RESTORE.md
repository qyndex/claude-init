# Approved temporary review pause

The operator explicitly approved pausing the three Claude review workflows and removing only `review` and `security-review` from live main required checks. All seven remaining required checks passed on candidate `80244b7aaec53e0e454ab3fa8971511e67dda8d9`. PR #50 merged and closed at 2026-10-09T10:44:26Z, squash SHA `148238ad8950681d352985cdb9c48ad0301e97d3`.

Claude returned HTTP 429 `usage_limit_reached`, with reset October 13 at 10:00 UTC (21:00 Sydney). Reviews remain paused until deliberately restored; this record does not schedule restoration. The factory bootstrap policy remains disabled.

After restoring available review capacity, compare the live ruleset with `ruleset-paused.json`. Preserve subsequent operator changes; restore the two removed check entries rather than blindly overwriting a changed ruleset. If unchanged, restore the saved full body:

```bash
gh api repos/qyndex/claude-init/rulesets/19653920 --method PUT --input docs/audits/2026-10-09/review-pause/ruleset-before.json
gh workflow enable 284902530 --repo qyndex/claude-init
gh workflow enable 284902533 --repo qyndex/claude-init
gh workflow enable 285347111 --repo qyndex/claude-init
```

Trigger actual reviews on the next candidate and verify current-head review outputs; skipped action success is insufficient.

PR #52 synchronizes the repository baseline with the approved live pause. Restore the repository baseline from `repository-ruleset-before.json` in the same change that restores live requirements. Factory policy continues to require both reviews and remains disabled.
