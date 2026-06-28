#!/usr/bin/env bash
# Promote the canary to the next step (or all steps with --full).
# Usage: bash scripts/promote.sh [--full]
set -euo pipefail

ROLLOUT_NAME="${ROLLOUT_NAME:-app}"
NAMESPACE="${NAMESPACE:-default}"

FULL=""
[[ "${1:-}" == "--full" ]] && FULL="--full"

echo "==> Checking rollout status..."
kubectl argo rollouts get rollout "$ROLLOUT_NAME" -n "$NAMESPACE"

echo ""
if [[ -n "$FULL" ]]; then
  echo "==> Promoting ALL remaining steps (skipping analysis and pauses)..."
else
  echo "==> Promoting past the current pause to the next step..."
fi

kubectl argo rollouts promote "$ROLLOUT_NAME" -n "$NAMESPACE" $FULL

echo ""
echo "==> Watching rollout progress (Ctrl+C to stop watching)..."
kubectl argo rollouts get rollout "$ROLLOUT_NAME" -n "$NAMESPACE" --watch
