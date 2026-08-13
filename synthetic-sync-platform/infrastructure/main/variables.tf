variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "name_prefix" {
  type    = string
  default = "incident-agent-poc"
}

variable "log_retention_days" {
  type    = number
  default = 14
}
