variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "name_prefix" {
  type    = string
  default = "incident-agent-poc"
}

variable "github_repo" {
  description = <<-EOT
    GitHub owner/repo allowed to assume the deploy role, using GitHub's
    immutable-ID OIDC sub format: owner@ownerId/repo@repoId. Verify with:
      gh api users/<owner> --jq '.id'
      gh api repos/<owner>/<repo> --jq '.id'
  EOT
  type        = string
  default     = "IndikaWeerakoon@24726173/elavate-2026@1332939682"
}
