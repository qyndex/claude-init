# Observability — Langfuse via native OTEL

> **Scope: this doc is the FACTORY's observability** — tracing the Claude Code agents themselves (cost, tokens, hierarchical agent calls). For the **SHIPPED APP's** production observability (OTEL collector, SLO burn-rate alerting, synthetic monitors, PagerDuty/Slack routing, Sentry release tracking → hotfix pipeline) see **[docs/PROD-OBSERVABILITY.md](PROD-OBSERVABILITY.md)** + the `prod-observability` skill. Two different planes — don't conflate them.

Round 6 Batch A. Wires Claude Code's built-in OpenTelemetry exporter to Langfuse Cloud (or self-host) so every agent invocation, tool call, LLM request, hook, and cost shows up in one unified trace tree.

## Why Langfuse

Claude Code emits a complete span tree natively: `claude_code.interaction → llm_request / tool / hook`, with `agent_id` + `parent_agent_id` linking subagents to their parents. Langfuse consumes OTLP/HTTP directly, renders cost from token counts, and groups hierarchical agent calls visually. No glue code: two env vars + a base64 auth header.

## Setup

### 1. Get Langfuse keys

**Cloud (recommended):**
1. Sign up at [cloud.langfuse.com](https://cloud.langfuse.com) (Hobby tier free; 50k units/mo; 30-day retention)
2. Create a project → Settings → API keys
3. Copy `public_key` (starts `pk-lf-`) and `secret_key` (starts `sk-lf-`)

**Self-host:** see `docs/LANGFUSE-SELFHOST.md` (Postgres + ClickHouse + Redis + S3 stack)

### 2. Drop keys outside the repo

```bash
mkdir -p ~/.config/langfuse
cat > ~/.config/langfuse/keys.env <<'EOF'
LANGFUSE_PUBLIC_KEY=pk-lf-xxxxxxxxxxxxxxxxxxxxxxxx
LANGFUSE_SECRET_KEY=sk-lf-xxxxxxxxxxxxxxxxxxxxxxxx
# Cloud EU (default) — uncomment for US or self-host:
# LANGFUSE_HOST=https://us.cloud.langfuse.com
# LANGFUSE_HOST=https://langfuse.your-company.internal
EOF
chmod 600 ~/.config/langfuse/keys.env
```

That's it. The next `claude` invocation reads `.claude/settings.json` env block, runs `.claude/scripts/langfuse-otel-headers.sh` to inject the auth header, and starts emitting OTLP spans.

### 3. Verify

```bash
# Smoke-test the headers script
bash .claude/scripts/langfuse-otel-headers.sh
# Should print {"Authorization": "Basic ...", "x-langfuse-ingestion-version": "4"}

# Start a Claude session; in 60s the first batch lands in Langfuse
claude
> hello
```

Open `https://cloud.langfuse.com/project/<id>/traces` — you'll see one trace per `claude_code.interaction` with nested spans for every tool call.

## What's traced

| Span name | Type | Data |
|---|---|---|
| `claude_code.interaction` | root span per user message | session_id, turn_count, total tokens, total cost |
| `claude_code.llm_request` | each LLM call | model, input_tokens, output_tokens, cache_read_tokens, ttft_ms, stop_reason |
| `claude_code.tool` | each tool call | tool_name, agent_id, parent_agent_id, result_tokens, file_path (if Read/Edit/Write) |
| `claude_code.hook` | each hook fire | hook_name, exit_code, duration |

## Multi-agent linkage

Already free: every subagent span carries `parent_agent_id`. The Task tool nests subagent `llm_request` spans under the parent's `claude_code.tool` span. Langfuse renders this as a tree.

For `claude --bg` swarm streams: `swarm-dispatch.sh` propagates `TRACEPARENT` env var so streams nest under the coordinator's root trace. To make this work, the coordinator must write its current traceparent to `.swarms/coordinator/.traceparent` before dispatching (todo: add this to coordinator agent's workflow).

## PII redaction — locked defaults

```
OTEL_LOG_USER_PROMPTS=0       # user messages NEVER sent
OTEL_LOG_TOOL_CONTENT=0       # tool inputs/outputs NEVER sent
OTEL_LOG_RAW_API_BODIES=0     # raw API bodies NEVER sent
OTEL_LOG_TOOL_DETAILS=1       # file paths + tool names ARE sent
```

What this means: Langfuse sees that you ran `Read /Volumes/M/.../auth.ts`, not the file's contents. Sees that the architect agent invoked the researcher subagent, not their conversation.

**To debug**, temporarily flip `OTEL_LOG_TOOL_CONTENT=1` for that session. Remember to flip back.

**Note**: `file_path` attributes include absolute paths. If your repo path is sensitive (`/Users/jane/clients/acme/`), set `OTEL_LOG_TOOL_DETAILS=0` and accept loss of file-level visibility.

## Cost ceiling

| Activity | Spans/day |
|---|---|
| Solo dev, ~50 interactions/day | ~1,500 |
| 5-stream swarm dispatch | ~6,000 |
| Overnight Cloud Routine | ~3,000 |

Hobby tier = 50,000 units/month. ~30 days × 1,500 = 45k → fits. Five swarm dispatches/mo + Cloud Routines pushes over. Upgrade to Core ($29/mo, 100k units, 90-day retention) when you cross.

Lower span volume by raising `OTEL_METRIC_EXPORT_INTERVAL` (default 60s) or setting `OTEL_LOG_TOOL_DETAILS=0`.

## What Langfuse does NOT replace

| In-harness | Langfuse | Reason |
|---|---|---|
| `.claude/memory/` (ADRs, patterns, incidents, in-flight) | — | Langfuse is observability, not knowledge |
| `cost-report.sh` + budget statusline + `pre-spawn-cost-gate.sh` | — | Synchronous; Langfuse latency would break the gate |
| Security hooks (`pre-bash-guard`, `pre-write-secret-scan`) | — | Block decisions need exit-code-2, not retrospective traces |
| Git history + Conventional commit trailers | — | Durable, signed record |
| `fleet.json` swarm state | — | Coordinator needs synchronous reads |
| `workflow-state.json`, `instinct-observer` | — | Local-only behavioral state |

Langfuse **adds**: visual trace tree, per-agent cost rollup, latency percentiles, error grouping, prompt diffs, eval scoring.

## Failure modes

- **Langfuse unreachable**: Claude Code keeps working; the OTLP exporter logs to stderr at `--debug`. Local hooks remain source of truth for cost gating.
- **Keys file missing**: `langfuse-otel-headers.sh` returns `{}`; Claude tries unauthenticated; Langfuse returns 401; traces drop silently. Harness still works.
- **Subscription switch**: keys file lives at `~/.config/langfuse/keys.env` (per-user, not per-project, not auth-principal-scoped). Survives Anthropic subscription changes. Survives `~/.claude/` wipe. Lost on `~/.config/` wipe.
- **Network outage**: OTLP exporter batches + retries in-process; doesn't block user turns. Worst case: lost spans.

## Sample trace payload

What one Read tool call inside a subagent looks like in Langfuse:

```json
{
  "trace_id": "5f8d3e8c2a4b7f9e1d6c0a2b4e7f9d1c",
  "observation_id": "a3b7c9d1e5f8",
  "parent_observation_id": "9e7c5a3b1d8f",
  "name": "claude_code.tool",
  "type": "SPAN",
  "start_time": "2026-05-28T14:23:11.412Z",
  "end_time":   "2026-05-28T14:23:11.518Z",
  "session_id": "01HZRXK3J9VYTQ2N7P4M8C6F0A",
  "metadata": {
    "tool_name": "Read",
    "agent_id": "researcher",
    "parent_agent_id": "main",
    "file_path": "/Volumes/M/.../session-end.sh",
    "result_tokens": 1840,
    "app.version": "2.1.144"
  }
}
```

The companion `claude_code.llm_request` span carries `gen_ai.system=anthropic`, `gen_ai.request.model=claude-sonnet-4-6`, token counts — Langfuse derives cost automatically.

## Disable

If you want to turn Langfuse off without removing config:

```bash
# Per-session:
CLAUDE_CODE_ENABLE_TELEMETRY=0 claude

# Permanently: edit .claude/settings.json env block, set CLAUDE_CODE_ENABLE_TELEMETRY=0.
```

Or delete `~/.config/langfuse/keys.env` — the headers script returns empty, traces stop landing.

## Sources

- Langfuse OTEL endpoint: https://langfuse.com/docs/opentelemetry/get-started
- Claude Code monitoring: https://code.claude.com/docs/en/monitoring-usage
- Langfuse pricing: https://langfuse.com/pricing
- Langfuse self-hosting: https://langfuse.com/self-hosting
