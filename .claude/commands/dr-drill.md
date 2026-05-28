---
description: Run a disaster recovery drill against a T1/T2 service. Measures RTO + RPO against declared targets in slo.yml; writes a postmortem-style report. Round 8 F.
argument-hint: "<service-name> [--dry-run]"
allowed-tools: Read, Glob, Grep, Bash, Edit, Write
disable-model-invocation: true
---

# /dr-drill — Disaster Recovery drill

```bash
service="${1:-}"
dry_run=0
[ "${2:-}" = "--dry-run" ] && dry_run=1

[ -z "$service" ] && { echo "Usage: /dr-drill <service> [--dry-run]"; exit 1; }

# Read declared RTO/RPO from slo.yml
if [ ! -f slo.yml ]; then
  echo "slo.yml not found — declare RTO/RPO first"
  exit 1
fi

target_rto=$(yq eval ".services.${service}.rto // \"unset\"" slo.yml 2>/dev/null || echo unset)
target_rpo=$(yq eval ".services.${service}.rpo // \"unset\"" slo.yml 2>/dev/null || echo unset)
runbook=$(yq eval ".services.${service}.runbook // \"unset\"" slo.yml 2>/dev/null || echo unset)

if [ "$target_rto" = "unset" ]; then
  echo "Service $service has no RTO/RPO declared in slo.yml — declare first."
  exit 1
fi

echo "→ DR drill: $service"
echo "  Declared RTO: $target_rto"
echo "  Declared RPO: $target_rpo"
echo "  Runbook: $runbook"
echo

if [ "$dry_run" = "1" ]; then
  echo "  [dry-run] would execute the drill per $runbook"
  exit 0
fi

mkdir -p .claude/memory/dr-drills
report=".claude/memory/dr-drills/${service}-$(date +%Y-%m-%d).md"

start_ts=$(date +%s)
start_iso=$(date -Iseconds)

cat > "$report" <<EOF
# DR drill: $service — $start_iso

## Declared targets
- RTO: $target_rto
- RPO: $target_rpo
- Runbook: $runbook

## Drill log

EOF

echo "→ 1. Cordon — marking service as drilling"
echo "[\$(date -Iseconds)] cordon: drilling=true" >> "$report"

echo "→ 2. Snapshot — capturing current state"
echo "[\$(date -Iseconds)] snapshot taken" >> "$report"

echo "→ 3. Trigger failure (sim or real per runbook)"
echo "  ACTION REQUIRED: follow $runbook section 'Trigger failure'"
echo "[\$(date -Iseconds)] failure triggered" >> "$report"

echo "→ 4. Time recovery"
echo "  ACTION REQUIRED: execute recovery per runbook; time the wall-clock"

read -p "Press enter when service is responding from standby/recovered..."
end_ts=$(date +%s)
elapsed_min=$(( (end_ts - start_ts) / 60 ))

echo "[\$(date -Iseconds)] service recovered after $elapsed_min min" >> "$report"

echo "→ 5. Verify integrity"
echo "  ACTION REQUIRED: run integrity check (known fixture, count, sample reads)"
read -p "Integrity check passed? (y/n): " integrity
echo "[\$(date -Iseconds)] integrity check: $integrity" >> "$report"

echo "→ 6. Compare RTO"
# Parse target RTO (handle "15m", "4h", "24h", "1d")
rto_min=$(echo "$target_rto" | awk '
  /^[0-9]+m$/ { gsub("m", ""); print; exit }
  /^[0-9]+h$/ { gsub("h", ""); print $0 * 60; exit }
  /^[0-9]+d$/ { gsub("d", ""); print $0 * 60 * 24; exit }
')
breach="no"
if [ "$elapsed_min" -gt "${rto_min:-99999}" ]; then
  breach="yes"
fi

cat >> "$report" <<EOF

## Result

- Actual recovery time: ${elapsed_min} min
- Target RTO: $target_rto (= ${rto_min:-?} min)
- Breach: $breach
- Integrity: $integrity

## Action items

EOF

if [ "$breach" = "yes" ]; then
  echo "  [ ] RTO breached — investigate; update runbook or redesign for faster recovery" >> "$report"
  echo "⚠ RTO BREACHED — recovery took ${elapsed_min} min vs target ${rto_min} min"
fi
if [ "$integrity" != "y" ]; then
  echo "  [ ] Integrity check failed — investigate restore path; backup may be corrupt" >> "$report"
fi
echo "  [ ] Update runbook with lessons learned" >> "$report"
echo "  [ ] Schedule next drill (90 days from $start_iso)" >> "$report"

echo "→ 7. Restore primary"
echo "  ACTION REQUIRED: failback per runbook"

# Update slo.yml with last_drill date
yq eval -i ".services.${service}.last_drill = \"$(date +%Y-%m-%d)\"" slo.yml 2>/dev/null || true

echo
echo "✓ Drill complete — report at $report"
echo "  Auto-create followup tasks from action items: bash .claude/scripts/findings-to-tasks.sh $report --priority incident-followup --source dr-drill"
```

## When to run

- Quarterly per T1/T2 service (mandatory)
- After any RUNBOOK update (proves the new runbook works)
- After any major architecture change (proves recovery still works against the new topology)

## Hard rules

- **A T1 service whose `last_drill` is >90 days old fails the harness-doctor gate.** No exceptions.
- **The report is permanent.** Even successful drills generate post-mortem-style records in `.claude/memory/dr-drills/`.
- **A failed drill is not optional learning — it's a P1 incident.** Open it; assign owners; track to fix.
- **Drills run against staging/dr-test environments, never prod.** Unless prod is the only realistic test (the rare case — drill with a maintenance window).

$ARGUMENTS
