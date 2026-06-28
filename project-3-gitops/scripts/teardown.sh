#!/usr/bin/env bash
# Removes ArgoCD Applications, then destroys the ArgoCD + Argo Rollouts Terraform resources.
# Does NOT destroy the EKS cluster (that is Project 2's responsibility).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DEV="$SCRIPT_DIR/../infra/environments/dev"

AWS_REGION="${AWS_REGION:-us-east-1}"

cd "$INFRA_DEV"
CLUSTER_NAME="$(terraform output -raw cluster_name 2>/dev/null || echo "")"

if [[ -n "$CLUSTER_NAME" ]]; then
  echo "==> Updating kubeconfig..."
  aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" 2>/dev/null || true

  echo "==> Deleting ArgoCD Applications (allows ArgoCD to clean up managed resources)..."
  kubectl delete application portfolio-app -n argocd --ignore-not-found
  kubectl delete application root -n argocd --ignore-not-found
  sleep 15
fi

echo ""
echo "==> About to destroy ArgoCD + Argo Rollouts Terraform resources."
echo "    EKS cluster (Project 2) will NOT be affected."
echo "    You have 10 seconds to cancel (Ctrl+C)."
sleep 10

terraform destroy -auto-approve

echo ""
echo "==> Project 3 infrastructure destroyed."
echo "    To also destroy EKS: cd project-2-containers && bash scripts/teardown.sh"
