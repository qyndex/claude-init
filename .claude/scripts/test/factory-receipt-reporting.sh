#!/usr/bin/env bash
# AC-2/AC-6/AC-7/AC-8: selected consumers and protected transfer integration.
set -euo pipefail
cd "$(dirname "$0")/../../.."
checks=(
  factory-reporting-context.sh
  factory-reporting-cli-selection.sh
  factory-hosted-digest-cli.sh
  factory-reporting-driver-workflow.sh
  factory-reporting-driver.sh
  factory-reporting-state-view.sh
  factory-reporting-receipt-transfer.sh
  factory-reporting-queue-evidence-source.sh
  factory-reporting-queue-immutable.sh
  factory-reporting-queue-scheduled.sh
  factory-receipt-discovery-review.sh
  factory-receipt-stage-anchor.sh
  factory-reporting-compare-cache.sh
  factory-reporting-maintenance-liveness.sh
  factory-digest-confirm.sh
)
for check in "${checks[@]}"; do
  bash ".claude/scripts/test/$check"
done
