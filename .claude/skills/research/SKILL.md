---
name: research
description: Ground a decision in evidence. Delegates to researcher agent. Produces a citation-heavy comparison brief saved under docs/research/. Use when a non-trivial choice (library, pattern, API) needs evidence beyond what the codebase shows.
when_to_use: User asks "which library", "what's the best way to", "research X", "compare Y vs Z", or any decision the architect/planner can't answer from local evidence.
argument-hint: "<research question>"
model: sonnet
allowed-tools: Read, Glob, Grep, WebSearch, WebFetch, Write, Edit
context: fork
agent: researcher
---

# Research

No claim without a citation. No vibes.

## Process

1. Sharpen the question with the user (one round, ≤ 2 follow-ups).
2. Identify 3-5 candidate options.
3. Pull each option's GitHub repo + official docs + reputable benchmark.
4. Fill the comparison table.
5. Write the brief.
6. Save to `docs/research/<date>-<topic>.md`.
7. Add a reference memory entry pointing to the brief.

## Sources, ranked

1. Official docs and primary repositories
2. Maintainer-written README and CHANGELOG
3. Recent (last 12 months) benchmarks from neutral parties
4. Recent blog posts from the maintainer or well-known practitioners
5. Recent (last 24 months) academic papers

Older sources note the date and flag as "verify still current".

## Output

See `.claude/agents/specialists/researcher.md` for the brief format.

After save: "Research brief at docs/research/<date>-<topic>.md. Recommendation: <option>. <Sources count> sources cited."
