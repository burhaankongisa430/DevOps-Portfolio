# Reuses the same S3 bucket created in Project 1 bootstrap.
# Key uses project-3 prefix so state is isolated from P1 and P2.
terraform {
  backend "s3" {
    bucket         = "REPLACE_WITH_P1_BOOTSTRAP_state_bucket_name"
    key            = "project-3/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "REPLACE_WITH_P1_BOOTSTRAP_dynamodb_table_name"
    encrypt        = true
  }
}
