# Use the same S3 bucket created by the Project 1 bootstrap.
# Key is different (project-2) so state is isolated from P1.
terraform {
  backend "s3" {
    bucket         = "REPLACE_WITH_P1_BOOTSTRAP_state_bucket_name"
    key            = "project-2/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "REPLACE_WITH_P1_BOOTSTRAP_dynamodb_table_name"
    encrypt        = true
  }
}
