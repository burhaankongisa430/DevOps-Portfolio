# Step 1: cd bootstrap && terraform init && terraform apply
# Step 2: copy the `backend_config_snippet` output and paste it here,
#         replacing the placeholder values below.
# Step 3: terraform init  (Terraform will migrate state to the S3 backend)

terraform {
  backend "s3" {
    bucket         = "REPLACE_WITH_BOOTSTRAP_state_bucket_name"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "REPLACE_WITH_BOOTSTRAP_dynamodb_table_name"
    encrypt        = true
  }
}
