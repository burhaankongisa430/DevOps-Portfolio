#!/usr/bin/env bash
# Initialises and applies the dev environment end-to-end.
# Prerequisites: AWS credentials configured, TF_VAR_db_password set.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$SCRIPT_DIR/../bootstrap"
DEV_DIR="$SCRIPT_DIR/../environments/dev"

: "${TF_VAR_db_password:?Set TF_VAR_db_password before running this script}"

echo "==> [1/4] Bootstrapping remote state..."
cd "$BOOTSTRAP_DIR"
terraform init -upgrade
terraform apply -auto-approve

echo ""
echo "==> [2/4] Updating backend.tf with bootstrap outputs..."
BUCKET=$(terraform output -raw state_bucket_name)
TABLE=$(terraform output -raw dynamodb_table_name)
REGION=$(terraform output -json | python3 -c "import sys,json; print(json.load(sys.stdin).get('aws_region',{}).get('value','us-east-1'))" 2>/dev/null || echo "us-east-1")

cd "$DEV_DIR"
sed -i "s|REPLACE_WITH_BOOTSTRAP_state_bucket_name|$BUCKET|g" backend.tf
sed -i "s|REPLACE_WITH_BOOTSTRAP_dynamodb_table_name|$TABLE|g" backend.tf

echo "==> [3/4] Initialising dev environment with remote backend..."
terraform init -upgrade

echo ""
echo "==> [4/4] Planning and applying dev environment..."
terraform plan -out=tfplan
terraform apply tfplan
rm -f tfplan

echo ""
echo "==> Done."
terraform output app_url
