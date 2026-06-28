#!/usr/bin/env bash
# Removes the Helm release and destroys the EKS + ECR infrastructure.
# Project 1 resources (VPC, RDS, etc.) are NOT touched — destroy those separately.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
INFRA_DEV="$ROOT_DIR/infra/environments/dev"

AWS_REGION="${AWS_REGION:-us-east-1}"
NAMESPACE="${NAMESPACE:-default}"

cd "$INFRA_DEV"
CLUSTER_NAME="$(terraform output -raw cluster_name 2>/dev/null || echo "")"

if [[ -n "$CLUSTER_NAME" ]]; then
  echo "==> Updating kubeconfig..."
  aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" 2>/dev/null || true

  echo "==> Removing Helm release 'app'..."
  helm uninstall app --namespace "$NAMESPACE" 2>/dev/null || echo "    (release not found — skipping)"

  echo "==> Waiting for ALB to be deprovisioned before destroying infra..."
  sleep 30
fi

echo ""
echo "==> About to destroy ALL Project 2 infrastructure (EKS, ECR)."
echo "    You have 10 seconds to cancel (Ctrl+C)."
sleep 10

terraform destroy -auto-approve

echo ""
echo "==> Project 2 infrastructure destroyed."
echo "    Project 1 (VPC, RDS, etc.) is still running — tear down separately if needed."
