variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "name_prefix" {
  type    = string
  default = "incident-agent-poc"
}

variable "github_repo" {
  description = "GitHub org/repo allowed to assume the deploy role, e.g. IndikaWeerakoon/elavate-2026"
  type        = string
  default     = "IndikaWeerakoon/elavate-2026"
}
