---
description: Run the full local health check — lint, typecheck, tests, harness validation. Same checks CI runs. Use before /ship or when something feels off.
argument-hint: ""
allowed-tools: Bash
disable-model-invocation: true
---

# /health — Local health check

Run the same checks CI runs, on your local tree. Stop at the first failure.

```!
echo "=== Harness validate ==="
bash .claude/scripts/validate.sh
```

```!
echo
echo "=== Lint ==="
bash .claude/scripts/lint.sh
```

```!
echo
echo "=== Typecheck ==="
bash .claude/scripts/typecheck.sh
```

```!
echo
echo "=== Unit tests ==="
bash .claude/scripts/test-unit.sh
```

```!
echo
echo "=== Integration tests ==="
bash .claude/scripts/test-integration.sh
```

After running, summarize in one line: PASS or which step failed.

If any check failed and the cause isn't obvious from the output, suggest `/debug "<failing step>"`.
