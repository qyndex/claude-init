---
name: observability
description: Scaffold structured logs, metrics, and trace spans for any new endpoint or service. Verify emissions in PR diffs. Enforce the observability rules from .claude/rules/backend.md mechanically (not just aspirationally).
when_to_use: A new endpoint, handler, job, or service is being added. User says "add observability", "instrument this", "scaffold logging". Implementer agent invokes this when backend.md rules apply.
allowed-tools: Read, Glob, Grep, Edit, Write, Bash
model: sonnet
---

# Observability

Every new endpoint emits: **one structured log** + **one latency metric** + **one error-rate metric** + **one trace span**. Enforced, not aspired.

## Per-endpoint checklist

```python
# Python (FastAPI / Django) example pattern — adapt per stack
import structlog
from opentelemetry import trace
from prometheus_client import Histogram, Counter

log = structlog.get_logger()
tracer = trace.get_tracer(__name__)
latency = Histogram("endpoint_latency_seconds", "Endpoint latency", ["endpoint", "method", "status"])
errors = Counter("endpoint_errors_total", "Endpoint errors", ["endpoint", "method", "error_class"])

async def handler(request):
    with tracer.start_as_current_span("endpoint.foo") as span:
        span.set_attribute("user_id", request.user_id)
        try:
            with latency.labels("foo", "GET", "200").time():
                result = await do_work()
            log.info("foo.success", user_id=request.user_id, duration_ms=...)
            return result
        except Exception as e:
            errors.labels("foo", "GET", type(e).__name__).inc()
            log.error("foo.failure", user_id=request.user_id, error=str(e), exc_info=True)
            raise
```

## Required emissions (PR-verified)

| Tier | What | Why |
|---|---|---|
| 1 | Structured INFO log (timestamp, request_id, user_id, endpoint, duration_ms, status) | Trace per-request |
| 2 | ERROR log with stack + request_id | Debug failures |
| 3 | Latency Histogram per endpoint | SLO measurement |
| 4 | Error counter per (endpoint, error_class) | SLO + alerting |
| 5 | Trace span with endpoint name + key attrs | Cross-service tracing |

## PII redaction

Never log:
- password, raw token, API key, session cookie
- full credit card, full SSN, raw OAuth refresh token
- raw email body, raw chat message content

Use field-level redaction at the logger level (structlog processors, Pino redact, etc.).

## Verification (mechanical)

The `verify-loop` skill checks for these emissions in the diff:
```bash
# Look for log.info / log.error / increment / span starts in new endpoint code
rg -A 5 -B 2 'async def \w+_handler|^def \w+_handler' new_files \
  | rg -q 'log\.(info|error)|span\.|latency\.labels|errors\.labels' || \
  echo "MISSING: endpoint has no observability emissions"
```

For TypeScript: equivalent ripgrep on `logger.info/error`, `metrics.increment`, `tracer.startSpan`.

## Hard rules

- **No new endpoint without observability emissions.** Enforced at verify-loop.
- **No PII in logs.** Enforced by `/pii-audit` and structlog/Pino field redaction.
- **No silent error swallow.** If you catch, you log (with stack) AND re-raise OR explicit suppression note.
- **Tier 1 services emit traces too.** T2/T3 can emit just logs + metrics.

## References

- `.claude/rules/backend.md` — the aspirational rule this skill enforces
- `slo.yml` — the SLO targets these emissions feed
- OpenTelemetry docs: https://opentelemetry.io/
- Structlog: https://www.structlog.org/
