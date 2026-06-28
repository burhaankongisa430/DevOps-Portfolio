project     = "devops-portfolio"
environment = "dev"
aws_region  = "us-east-1"

# Same bucket used for P1 and P2 state:
#   cd ../../project-1-iac/bootstrap && terraform output state_bucket_name
state_bucket = "REPLACE_WITH_P1_BOOTSTRAP_state_bucket_name"
