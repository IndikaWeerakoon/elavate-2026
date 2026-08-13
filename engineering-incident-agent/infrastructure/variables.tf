variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "name_prefix" {
  type    = string
  default = "incident-agent-poc-openclaw"
}

variable "instance_type" {
  type    = string
  default = "t4g.medium"
}

variable "key_name" {
  description = "Existing EC2 key pair name (create out-of-band, e.g. aws ec2 create-key-pair)"
  type        = string
  default     = "incident-agent-poc-openclaw"
}

variable "ssh_ingress_cidr" {
  description = "CIDR allowed to SSH in, e.g. \"1.2.3.4/32\". No public 0.0.0.0/0 default — set explicitly."
  type        = string
}

variable "root_volume_gb" {
  type    = number
  default = 30
}
