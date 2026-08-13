terraform {
  backend "s3" {
    bucket         = "incident-agent-poc-tfstate-927676118813"
    key            = "synthetic-sync-platform/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "incident-agent-poc-tfstate-lock"
    encrypt        = true
  }
}
