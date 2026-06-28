#!/usr/bin/env bash
# One-time setup: apply Terraform (ArgoCD + Argo Rollouts), then bootstrap the
# App-of-Apps so ArgoCD takes over all future deployments.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DEV="$SCRIPT_DIR/../infra/environments/dev"
ARGOCD_APPS="$SCRIPT_DIR/../argocd"

AWS_REGION="${AWS_REGION:-us-east-1}"

echo "==> [1/4] Applying Terraform (installs ArgoCD + Argo Rollouts)..."
cd "$INFRA_DEV"
terraform init -upgrade
terraform apply -auto-approve

CLUSTER_NAME="$(terraform output -raw cluster_name)"

echo ""
echo "==> [2/4] Updating kubeconfig..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo ""
echo "==> [3/4] Waiting for ArgoCD to become ready..."
kubectl wait --for=condition=available \
  deployment/argocd-server \
  -n argocd \
  --timeout=300s

echo ""
echo "==> [4/4] Bootstrapping the App-of-Apps root Application..."
echo "    IMPORTANT: update the repoURL in argocd/apps/root.yaml and"
echo "    argocd/apps/portfolio-app.yaml to point to your GitHub repo first."
echo ""
read -rp "    Have you updated the repoURL values? [y/N]: " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborting — update the repoURL values first."; exit 1; }

kubectl apply -f "$ARGOCD_APPS/projects/portfolio.yaml"
kubectl apply -f "$ARGOCD_APPS/apps/root.yaml"

echo ""
echo "==> Bootstrap complete."
echo ""
echo "    ArgoCD UI:     kubectl port-forward svc/argocd-server -n argocd 8080:80"
echo "                   then open http://localhost:8080"
echo ""
echo "    Admin password: $(kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d)"
echo ""
echo "    Rollouts dashboard: kubectl port-forward svc/argo-rollouts-dashboard \\"
echo "                         -n argo-rollouts 3100:3100"
echo "                        then open http://localhost:3100"
echo ""
echo "    To trigger a deploy: update image.tag in argocd/apps/portfolio-app.yaml and push."
