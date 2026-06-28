#!/usr/bin/env bash
# Immediately abort a canary — returns 100% traffic to the stable version.
# See docs/runbook-rollback.md for the full rollback procedure.
set -euo pipefail

ROLLOUT_NAME="${ROLLOUT_NAME:-app}"
NAMESPACE="${NAMESPACE:-default}"

echo "==> Aborting rollout '$ROLLOUT_NAME' in namespace '$NAMESPACE'..."
echo "    Traffic will return to the stable version immediately."
echo ""

kubectl argo rollouts abort "$ROLLOUT_NAME" -n "$NAMESPACE"

echo ""
echo "==> Watching abort complete (Ctrl+C to stop)..."
kubectl argo rollouts get rollout "$ROLLOUT_NAME" -n "$NAMESPACE" --watch
