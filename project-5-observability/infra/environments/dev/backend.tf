terraform {
  backend "s3" {
    bucket         = "REPLACE_WITH_P1_BOOTSTRAP_state_bucket_name"
    key            = "project-5/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "REPLACE_WITH_P1_BOOTSTRAP_dynamodb_table_name"
    encrypt        = true
  }
}
