#!/usr/bin/env bash
# Builds the Docker image and pushes it to ECR.
# Prerequisites: AWS CLI configured, Docker running, Terraform applied.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
APP_DIR="$ROOT_DIR/app"
INFRA_DEV="$ROOT_DIR/infra/environments/dev"

AWS_REGION="${AWS_REGION:-us-east-1}"
GIT_SHA="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo "local")"
VERSION="${VERSION:-sha-${GIT_SHA}}"
BUILD_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "==> Fetching ECR repository URL from Terraform state..."
cd "$INFRA_DEV"
ECR_URL="$(terraform output -raw ecr_repository_url)"

echo "==> Authenticating Docker to ECR..."
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "${ECR_URL%%/*}"

echo "==> Building image: $ECR_URL:$VERSION"
docker build \
  --build-arg VERSION="$VERSION" \
  --build-arg BUILD_TIME="$BUILD_TIME" \
  --tag "$ECR_URL:$VERSION" \
  --tag "$ECR_URL:latest" \
  "$APP_DIR"

echo "==> Pushing to ECR..."
docker push "$ECR_URL:$VERSION"
docker push "$ECR_URL:latest"

echo ""
echo "==> Image pushed successfully."
echo "    Repository : $ECR_URL"
echo "    Tag        : $VERSION"
echo "    Latest tag : latest"
echo ""
echo "Next step: bash scripts/deploy.sh $VERSION"
