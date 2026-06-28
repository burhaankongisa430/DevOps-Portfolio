project     = "devops-portfolio"
environment = "dev"
aws_region  = "us-east-1"

# db_password is intentionally absent here — set it as an environment variable:
#   export TF_VAR_db_password="choose-a-strong-password"
# Never commit a plaintext password to version control.
