#!/usr/bin/env bash
# Deploys or upgrades the application on EKS using Helm.
# Usage: bash scripts/deploy.sh [IMAGE_TAG]
# If IMAGE_TAG is omitted, defaults to "latest".
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
INFRA_DEV="$ROOT_DIR/infra/environments/dev"

IMAGE_TAG="${1:-latest}"
AWS_REGION="${AWS_REGION:-us-east-1}"
NAMESPACE="${NAMESPACE:-default}"

echo "==> Fetching cluster info from Terraform state..."
cd "$INFRA_DEV"
ECR_URL="$(terraform output -raw ecr_repository_url)"
CLUSTER_NAME="$(terraform output -raw cluster_name)"

echo "==> Updating kubeconfig for cluster: $CLUSTER_NAME"
aws eks update-kubeconfig \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME"

echo "==> Deploying app version: $IMAGE_TAG"
helm upgrade --install app "$ROOT_DIR/helm/app" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --values "$ROOT_DIR/helm/app/values-dev.yaml" \
  --set "image.repository=$ECR_URL" \
  --set "image.tag=$IMAGE_TAG" \
  --atomic \
  --timeout 5m \
  --wait

echo ""
echo "==> Deployment complete."
kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=app"
echo ""
echo "==> Ingress endpoint:"
kubectl get ingress -n "$NAMESPACE" app 2>/dev/null \
  | awk 'NR>1 {print "    http://" $4}' \
  || echo "    (ingress address not yet assigned — the ALB may take 60–90s to provision)"
