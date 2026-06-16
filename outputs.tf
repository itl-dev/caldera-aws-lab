output "server_instance_id" {
  value = aws_instance.server.id
}

output "server_private_ip" {
  value = aws_instance.server.private_ip
}

output "server_public_ip" {
  value = aws_instance.server.public_ip
}

# Browser-only UI access (needs var.ui_cidr to allow your browser's IP on 443).
# Self-signed cert -> accept the one-time browser warning. Works through 443-only firewalls.
output "ui_url" {
  value = "https://${aws_instance.server.public_ip}  (login red/admin; accept the self-signed cert warning)"
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

# Browser-based RDP to the victims (no client/key). Printed in full only when
# Guacamole is enabled, so students can copy the URL + portal credentials straight
# from `terraform apply` output. Password is shown in the clear (nonsensitive) on
# purpose: it is random per-deploy and only useful while this lab is up. Needs
# ui_cidr to allow your browser's IP on 443.
output "guacamole" {
  value = var.enable_guacamole ? join("\n", [
    "",
    "  URL : https://${aws_instance.server.public_ip}/guac/   (accept the self-signed cert warning)",
    "  User: student",
    "  Pass: ${nonsensitive(random_password.guac_login.result)}",
    "  Then open connection 'caldera-victim-1'. (Your IP must be allowed via ui_cidr.)",
  ]) : "guacamole disabled (enable_guacamole=false)"
}

# Machine-readable single fields (for scripts).
output "guacamole_url" {
  value = var.enable_guacamole ? "https://${aws_instance.server.public_ip}/guac/" : "n/a (enable_guacamole=false)"
}

# Login for the Guacamole portal: `terraform output -raw guacamole_login`
output "guacamole_login" {
  value     = var.enable_guacamole ? "student / ${random_password.guac_login.result}" : "n/a"
  sensitive = true
}

# Victim Windows Administrator password (set on first boot). For direct RDP via
# rdp_cidr, or to log into the desktop once Guacamole has you on the session.
# View with: terraform output -raw victim_admin_password
output "victim_admin_password" {
  value     = random_password.victim_admin.result
  sensitive = true
}
