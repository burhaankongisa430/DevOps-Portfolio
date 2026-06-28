#!/usr/bin/env bash
# Destroys all dev resources to stop AWS charges.
# The S3 state bucket and DynamoDB lock table (bootstrap) are NOT destroyed
# automatically — they hold your Terraform history. Remove them manually
# from the bootstrap/ directory only if you are fully done with the project.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_DIR="$SCRIPT_DIR/../environments/dev"

: "${TF_VAR_db_password:?Set TF_VAR_db_password (needed even for destroy)}"

echo "==> About to destroy ALL dev resources."
echo "    You have 10 seconds to cancel (Ctrl+C)."
sleep 10

cd "$DEV_DIR"
terraform destroy -auto-approve

echo ""
echo "==> Dev environment destroyed."
echo "    Estimated monthly cost is now \$0 (excluding the state S3 bucket, which costs cents)."
echo ""
echo "    To also destroy the remote state backend:"
echo "      cd $SCRIPT_DIR/../bootstrap && terraform destroy"
