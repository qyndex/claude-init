# Roadmap (traceable)

Machine-readable companion to the root `roadmap.md`. One row per item; every `spec:NNN`
must resolve to a real spec. Schema + gate: see [README.md](README.md). Validated by the
`[roadmap-trace]` block in `.claude/scripts/validate.sh`.

Row format:

```
- [ ] <title> | spec:NNN | quarter:YYYY-Qn | status: planned|active|shipped
```

## Items

- [x] Traceability + decision harvest | spec:005 | quarter:2026-Q3 | status: active
- [x] CI gates fail on own code | spec:004 | quarter:2026-Q3 | status: shipped
