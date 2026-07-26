# Launch playbook

Everything needed to launch `claude-init` publicly and grow stars. Work top-to-bottom: the
**Pre-launch checklist** must be green before you post anywhere — a repo with red CI or no demo
converts poorly and you only get one first impression per channel.

---

## Pre-launch checklist (do these first)

- [ ] **Fix GitHub Actions billing.** Until then every PR shows all-red checks → reads as broken.
      This is the #1 credibility blocker. (Settings → Billing.)
- [ ] **Record the demo GIF** → `docs/launch/demo.gif`, uncomment it in the README. See
      [DEMO.md](DEMO.md). Nothing converts better than watching it ship.
- [ ] **Set the social preview image.** Convert `docs/launch/social-preview.svg` → PNG (1280×640)
      and upload at **Settings → Options → Social preview**:
      ```bash
      # needs rsvg-convert (brew install librsvg) or Inkscape
      rsvg-convert -w 1280 -h 640 docs/launch/social-preview.svg -o docs/launch/social-preview.png
      ```
      A blank share card kills click-through on X/LinkedIn/Slack.
- [ ] **Swap fake badges for real ones** once CI runs green (the `harness-validated` badge is
      currently a static shield, not live CI status):
      ```markdown
      [![CI](https://github.com/qyndex/claude-init/actions/workflows/harness-validate.yml/badge.svg)](https://github.com/qyndex/claude-init/actions/workflows/harness-validate.yml)
      ```
- [ ] **Cut a release.** `release-please` is wired — tag a `v1.0.0`. A tagged release + CHANGELOG
      reads as "real, maintained project."
- [ ] **Label 5–10 issues `good first issue`** and pin 1–2. Signals an active, welcoming project.

---

## Channels (highest ceiling first)

### 1. Hacker News — "Show HN"
Highest variance, highest ceiling for dev tools. Post **Tue–Thu, ~8–10am ET**. Title must be plain
and specific (no hype, no emoji):

> **Show HN: Claude-init – a spec-driven, TDD-first harness for Claude Code**

First comment (post it yourself immediately) — the "why I built this":

> I kept re-setting up the same `.claude/` scaffold for every project: a constitution, TDD hooks,
> verification gates, security guardrails, a spec→plan→tasks→ship workflow. claude-init packages
> that into one command you drop into any repo (greenfield or legacy — it reconciles safely and
> never clobbers your files). The opinions it encodes: spec before code, evidence before "done"
> (every task ships a red→green TDD ledger), and hooks that hard-block destructive commands before
> the agent acts. It's all shell + config, MIT, no build step. Happy to answer questions.

Then **stay in the thread all day** answering substantively. Engagement is the algorithm.

### 2. X / Twitter
Thread, not a link drop. Structure:
1. Hook + the demo GIF: *"I turned Claude Code into an autonomous engineering team. One command:"*
2. The install line as an image/code.
3. 3–4 tweets: the workflow, the safety model, the evidence gate — one screenshot each.
4. CTA: repo link + "★ if useful." Tag **@AnthropicAI**, **@claudeai**.
Repost into relevant replies where people complain about ungoverned AI coding.

### 3. Reddit
Genuine writeup, not a self-promo blurb (mods remove those). Good fits:
- **r/ClaudeAI** — most on-target.
- **r/LocalLLaMA**, **r/ChatGPTCoding**, **r/programming** (r/programming is strict — lead with the
  engineering ideas, not the product).
Frame around a problem you solved, link in the body, respond to every comment.

### 4. Awesome-lists (durable, compounding)
Submit PRs — see `docs/launch/awesome-submissions.md` for ready-to-paste entries:
- `awesome-claude-code`
- `awesome-ai-agents`
- `awesome-mcp` / `punkpeye/awesome-mcp-servers`

### 5. Communities
- **Anthropic Discord** / Claude Developers — share in the right channel, not everywhere.
- **dev.to / Hashnode** — a "How I set up an autonomous Claude Code workflow" post that happens to
  use claude-init pulls long-tail search traffic.

---

## Message discipline

- **Lead with the outcome, not the internals.** "autonomous engineering team in one command,"
  not "a curated `.claude/` scaffold with 25 hooks."
- **Show, don't tell.** The GIF and the one-liner do more than any paragraph.
- **Be honest about scope.** Deploy is BYO (a stub); say so. Honesty earns HN/Reddit trust; overclaiming gets torn apart.
- **Every reply is marketing.** The maintainer who answers thoughtfully for a day out-converts any headline.

---

## After launch

- Watch traffic: **Insights → Traffic** (referrers tell you which channel worked — double down).
- Turn recurring questions into README FAQ / docs.
- Ship visibly: tagged releases + a changelog keep returning visitors and signal momentum.
