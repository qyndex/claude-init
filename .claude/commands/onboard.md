---
description: Show the onboarding doc and walk a new team member through their first session. Friendly orientation — not for veterans.
argument-hint: ""
allowed-tools: Read, Bash
disable-model-invocation: true
---

# /onboard — Welcome a new team member

Open docs/ONBOARDING.md and walk through it interactively.

## Process

1. Read `docs/ONBOARDING.md` and `.claude/CLAUDE.md`.
2. Greet the user, ask their role (engineer / SRE / PM / designer).
3. Run `/status` to show current state.
4. Walk through the eight-phase workflow with one concrete example using a tiny "hello-world" spec.
5. Show where to find playbooks for common tasks.
6. End with: "When you're ready, try `/specify 'your first feature'`."

## Tone

- Patient, not patronizing.
- Show, don't just tell — run a real command after each explanation.
- Surface gotchas: secrets handling, hook gates, branch protection.
- Link back to specific files in docs/ for deeper reading.

## Format

Walk through 5-7 short sections, each with:
- One-line intro
- One command to run
- One sentence interpretation of the output
