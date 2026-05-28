---
name: 0000-feedback-template
description: Customer feedback registry — typed record for one signal. Round 7 C.
metadata:
  type: feedback
  status: template
# ─── identity ──────────────────────────────────────────────────────────
id: FB-YYYYMMDD-NNN
captured_at: YYYY-MM-DDTHH:MM:SS

# ─── source ────────────────────────────────────────────────────────────
source: sales-call | support-ticket | nps-comment | churn-interview | pendo-poll | slack-customer-channel | manual
source_ref: <fireflies-url | intercom-thread-id | call-transcript-path>
reporter: "@<internal-person-who-captured>"
written_by: feedback-extractor | human

# ─── customer ──────────────────────────────────────────────────────────
customer:
  account: "<name>"
  arr_band: SMB | MID | ENT      # <$10k | $10k-$100k | >$100k
  health: green | yellow | red
  contract_renewal: YYYY-MM-DD
  champion: "<name + role>"

# ─── content ───────────────────────────────────────────────────────────
verbatim_quote: "..."
problem_area: <product-surface>       # checkout | onboarding | search | billing | etc.
sentiment: blocker | frustration | suggestion | praise
business_signal: churn-risk | expansion-blocked | adoption-stalled | nps-detractor | retention-driver | quick-win
severity: P0 | P1 | P2 | P3
                                       # P0 = imminent churn / revenue at risk
                                       # P1 = strong negative signal across multiple accounts
                                       # P2 = improvement opportunity
                                       # P3 = nice-to-have

# ─── triage state ──────────────────────────────────────────────────────
status: new | triaged | in-spec | shipped | wont-do | dupe
dupe_of: FB-...                       # if status=dupe
triaged_by: "@<person>"
triaged_at: YYYY-MM-DDTHH:MM:SS

# ─── linkage ───────────────────────────────────────────────────────────
suggested_kr: KR-2026Q3-XX | unaligned
spec_refs: []                         # populated when feedback converts to a spec
initiative_refs: []                   # populated when feedback drives an initiative
pivot_refs: []                        # populated if feedback triggered a /pivot (Round 7)
related_feedback: []                  # other FB-ids in the same theme cluster
---

# Feedback FB-YYYYMMDD-NNN

## Verbatim quote

> "..."

## Context

What was the conversation/page/moment? Who said it (role, account)? When?

## Why it matters

1-3 bullet points on the business implication. Tie to a metric or KR if possible.

## Triage notes

Free-text from triage session. What questions did this raise? Who else should hear about this? What's the next step?

## Action taken

- [ ] Linked to spec: `<spec-id>` (date)
- [ ] Linked to initiative: `<initiative-id>` (date)
- [ ] Reproduced internally: <yes/no/url>
- [ ] Customer responded after action: <date + sentiment>

## References

- Source: <URL>
- Recording timestamp: <mm:ss if from a call>
- Slack thread: <link>
