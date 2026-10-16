#!/usr/bin/env bash
# AC-1..AC-8 local contracts only; live rollout is a separate explicit acceptance.
set -euo pipefail
cd "$(dirname "$0")/../../.."
checks=(
  factory-reporting-queue-journal
  factory-reporting-queue-cas
  factory-reporting-queue-observation
  factory-reporting-queue-delivery
  factory-reporting-queue-actions
  factory-reporting-queue-live-evidence
  factory-workflow-baseline
  factory-reporting-alerts
  factory-reporting-watchdog
  factory-hosted-digest
  factory-slack-attachment
  factory-policy-approval
)
for check in "${checks[@]}"; do
  printf 'Local contract: %s\n' "$check"
  bash ".claude/scripts/test/$check.sh"
done
printf '%s\n' 'Local contract contributions for AC-1..AC-8 passed. Full AC-8 live acceptance: PENDING; no live credit.'
