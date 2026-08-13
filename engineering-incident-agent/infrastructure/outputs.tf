output "instance_id" {
  value = aws_instance.openclaw.id
}

output "public_ip" {
  value = aws_eip.openclaw.public_ip
}

output "ssh_command" {
  value = "ssh -i ~/.ssh/elavate-2026/${var.key_name}.pem ubuntu@${aws_eip.openclaw.public_ip}"
}

output "gateway_tunnel_command" {
  description = "Gateway port 18789 is not publicly exposed — tunnel to reach the Control UI/WebChat"
  value       = "ssh -i ~/.ssh/elavate-2026/${var.key_name}.pem -L 18789:localhost:18789 ubuntu@${aws_eip.openclaw.public_ip}"
}
