output "server_instance_id" {
  value = aws_instance.server.id
}

output "server_private_ip" {
  value = aws_instance.server.private_ip
}

output "server_public_ip" {
  value = aws_instance.server.public_ip
}

output "victim_instance_ids" {
  value = aws_instance.victim[*].id
}

# View the UI through a restrictive firewall: run this, then open http://localhost:8888
# (CloudShell has session-manager-plugin preinstalled; on a laptop install it once.)
output "open_ui_via_ssm" {
  value = "aws ssm start-session --target ${aws_instance.server.id} --region ${var.region} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"8888\"],\"localPortNumber\":[\"8888\"]}'"
}

# Keyless shell into the server.
output "ssm_shell_server" {
  value = "aws ssm start-session --target ${aws_instance.server.id} --region ${var.region}"
}

# Check which agents have called back (default API key from conf/default.yml).
output "check_agents" {
  value = "aws ssm send-command --instance-ids ${aws_instance.server.id} --region ${var.region} --document-name AWS-RunShellScript --parameters 'commands=[\"curl -s -H \\\"KEY: ADMIN123\\\" http://localhost:8888/api/v2/agents\"]'"
}

output "ui_login_hint" {
  value = "CALDERA UI login: red/admin (or admin/admin). API key: ADMIN123 (default.yml via --insecure)."
}
