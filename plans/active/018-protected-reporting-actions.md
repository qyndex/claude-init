---
id: 018
slug: protected-reporting-actions
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
spec: specs/active/018-protected-reporting-actions.md
---

# Reporting Actions integration plan

Keep organization policy verification on a GitHub-hosted runner using an environment-held read-only organization token. The persistent runner receives only default-branch reporting jobs after server-policy verification. Runner group restrictions are mandatory; labels alone do not isolate a persistent state host. Build protected config without shell interpolation, validate private ownership/state location, and use a periodic UTC trigger with Sydney due-time selection. Separate reporting secrets from factory merge authority. Keep master activation unset until real positive/negative identity and delivery drills pass.

Host registration and organization permission setup are explicit operator/bootstrap tasks, not guessed infrastructure. Document UI runner-group setup so broad CLI admin:org refresh is optional.
