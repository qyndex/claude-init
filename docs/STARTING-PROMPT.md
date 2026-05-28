# The Starting Prompt — kicking off a new product from zero

> This is the **first message** you give the factory when starting a brand-new product. It tells the
> factory to *interview you thoroughly first* (ask everything it needs up front), then build the
> roadmap, then deliver it end-to-end in safe phased increments.
>
> Two ways to use it:
> - **Quick:** type `/kickoff` (wraps this whole prompt — see `.claude/commands/kickoff.md`).
> - **Explicit:** paste the template below into a fresh Claude Code session in your repo.

---

## How it works (what to expect)

1. **Interview.** The factory uses the `grill-me` skill to interrogate you — vision, users,
   jobs-to-be-done, success metrics, constraints, non-goals, integrations, risk tolerance, rollout
   policy. It asks in small batches and pushes back on vagueness. **This is the most important
   step** — answer honestly; "I don't know yet" is a valid answer and becomes an open question.
2. **Roadmap.** It synthesizes your answers into `OKRs.md`, `roadmap.md`, and the first
   `initiatives/active/<id>.md` — phased so each phase ships independently.
3. **Confirm.** It shows you the roadmap and the proposed first slice and **waits for your approval**
   before writing any code.
4. **Deliver.** It runs the eight-phase workflow (specify → … → ship) for the first phase, shipping
   behind feature flags, and can continue overnight via autopilot.

You stay in control: it stops at every irreversible gate (spec approval, merge, deploy, ramp).

---

## The template (copy-paste this)

```text
You are the lead of an autonomous software factory. We are starting a NEW product from zero.
Follow the project constitution in .claude/CLAUDE.md at all times.

PHASE 0 — INTERVIEW ME FIRST (do this before anything else):
Invoke the grill-me skill and interrogate me until you could brief a new engineer with no gaps.
Ask in small batches (3–5 questions at a time), push back on vague answers, and don't move on
while material unknowns remain. Cover at least:
  1. Product vision — in one sentence, what is this and who is it for?
  2. Target users & their top 3 jobs-to-be-done (the problems they're hiring us to solve).
  3. Success metrics — how will we know it's working? (north-star metric + 2–3 KRs)
  4. Scope for v1 — the smallest thing that delivers real value. What's explicitly OUT.
  5. Constraints — tech stack preferences, compliance (PII/PCI/HIPAA/SOC2), budget, deadlines.
  6. Existing assets — any repo, designs, APIs, data, brand, or infra to build on or integrate.
  7. Integrations — third-party services, auth providers, payment, email, analytics.
  8. Risk tolerance & rollout — how cautious? who are the first users we can safely expose?
  9. Non-negotiables — anything that must (or must never) be true.
Record anything I can't answer as an explicit open question; don't guess.

PHASE 1 — BUILD THE ROADMAP:
From my answers, produce (and show me for approval before coding):
  - OKRs.md: the north-star + 2–4 measurable KRs for v1.
  - roadmap.md: NOW / NEXT / LATER, with each item phased so every phase ships independently.
  - initiatives/active/<id>-<slug>.md: the first initiative, with appetite (time/budget),
    phase breakdown, risk register, and feature-flag namespace policy.
  - A one-paragraph "first slice" proposal: the thinnest end-to-end vertical we can ship to
    real (or staff) users to validate the riskiest assumption.
Verify latest stable versions of any proposed dependencies against the live registry
(per .claude/agents/core/architect.md) — never from memory.

PHASE 2 — CONFIRM:
Show me the roadmap + first slice. STOP and wait for my approval. Surface every open question.
Do not write production code until I approve.

PHASE 3 — DELIVER END-TO-END (after I approve):
For the approved first slice, run the eight-phase workflow from .claude/CLAUDE.md §VIII:
  /specify → /clarify → /plan → /tasks → /analyze → /implement (strict TDD) → /verify → /review → /ship
Ship DEFAULT-OFF behind a feature flag and ramp per the flag-rollout skill. Collect an evidence
bundle for every acceptance criterion. Open a PR for my review — never auto-merge, never deploy
without my explicit go. Then propose the next slice.

OPERATING RULES (always):
  - Spec before code; tests before implementation; evidence before "done."
  - Smallest viable design. No speculative features. Every changed line traces to a requirement.
  - Stop and ask when confused or when a decision is irreversible/strategic.
  - You may run unattended overnight via autopilot, but the merge button and prod deploy are mine.

Begin with PHASE 0 now — start interviewing me.
```

---

## Worked example (filled in)

Here's the same kickoff for a concrete product, so you can see the shape of a good answer set. You'd
paste the template above; this shows how the **interview** might go:

> **You paste the template.**
>
> **Factory (grill-me):**
> > Batch 1 of ~4. Let's pin the core:
> > 1. One sentence — what is this and who's it for?
> > 2. Who are the first users you can get in front of in week 1?
> > 3. What's the single riskiest assumption — the thing that, if wrong, sinks the product?
>
> **You:**
> > 1. A tool for freelance designers to send branded invoices and get paid by card.
> > 2. ~20 designers from my Discord who've said they'd try it.
> > 3. That they'll actually pay a monthly fee instead of using free PayPal invoicing.
>
> **Factory:**
> > Batch 2. Success + scope:
> > 4. North-star metric? (I'd propose: *# invoices paid per active user per month*.)
> > 5. For v1, is "create invoice → client pays by card → designer sees it paid" enough, or do
> >    you need recurring invoices / multi-currency / expense tracking on day one?
> > 6. Compliance: you're touching payments — do you want to hold card data (PCI burden) or use a
> >    processor like Stripe that keeps you out of PCI scope?
>
> **You:**
> > 4. Yes, that north-star works.
> > 5. Just the single-invoice flow for v1. Recurring is LATER. Multi-currency is out.
> > 6. Stripe — I never want to touch raw card data.
>
> **…(two more batches: stack preference = "React + Node, you pick the rest"; deadline = "soft 6
> weeks"; first users behind a staff flag; no HIPAA/SOC2 yet)…**
>
> **Factory (Phase 1 → Phase 2):**
> > Here's the roadmap:
> > - **OKR:** North-star = invoices paid / active user / month. KR1: 10 designers send ≥1 paid
> >   invoice in month 1. KR2: < 2 min from "create" to "send." KR3: payment success rate > 98%.
> > - **roadmap.md** — NOW: *Invoice→Pay vertical* (Stripe Checkout). NEXT: dashboard + reminders.
> >   LATER: recurring invoices, team accounts.
> > - **Initiative 001 — "Get Paid"**, appetite 6 weeks / \$X, 3 shippable phases.
> > - **First slice:** "Designer creates a one-off invoice, client pays via Stripe Checkout,
> >   designer sees it marked paid." Behind flag `invoice-pay-v1`, staff-only first.
> > Open question: do you want client accounts, or pay-by-link with no client login? (I recommend
> > pay-by-link for v1 — fewer steps to validate the core assumption.)
> > **Approve this slice, or adjust?**
>
> **You:** *"Pay-by-link, yes. Approved."*
>
> **Factory (Phase 3):** runs `/specify` … `/ship`, opens a PR with the evidence bundle, ramps the
> flag staff → 1% → … and proposes the dashboard slice next.

From a cold start, you answered ~15 questions and approved one slice. The factory turned that into a
roadmap and a shipping vertical.

---

## Tips for a good kickoff

- **Front-load the truth.** The interview is where you prevent months of wrong-direction work. Be
  blunt about constraints and the riskiest assumption.
- **"I don't know" is fine.** It becomes a tracked open question, not a silent guess.
- **Resist scope.** When the factory proposes the *thinnest* first slice, let it. You'll ship and
  learn faster. (It's trained to push back if you over-scope.)
- **You can stop any time.** Say "pause and show me the roadmap" or "/status" whenever you want a
  checkpoint.
- **After kickoff**, your day-to-day is the [Operator Manual](OPERATOR-MANUAL.md) runbook.

---

## See also
- [OPERATOR-MANUAL.md](OPERATOR-MANUAL.md) — how to run the factory day-to-day
- `.claude/skills/grill-me/SKILL.md` — the interrogation skill the interview uses
- `.claude/skills/specify/SKILL.md` — how specs are authored
- `.claude/commands/kickoff.md` — the `/kickoff` command that runs this prompt for you
