variable "region" {
  description = "Learner Lab allows us-east-1 / us-west-2. vockey exists only in us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "server_instance_type" {
  description = "CALDERA v5 UI build is happier with 8GB. Learner Lab cap is 'large'."
  type        = string
  default     = "t3.large"
}

variable "victim_instance_type" {
  description = "Windows wants >=4GB -> t3.medium. Learner Lab cap is 'large'."
  type        = string
  default     = "t3.medium"
}

variable "victim_count" {
  description = "How many Windows victims to launch (each auto-joins CALDERA). Mind the 9-instance Learner Lab cap."
  type        = number
  default     = 1
}

variable "key_name" {
  description = "Default Learner Lab key pair (us-east-1)."
  type        = string
  default     = "vockey"
}

variable "instance_profile" {
  description = "Pre-created profile (attaches LabRole) -> enables SSM Session Manager."
  type        = string
  default     = "LabInstanceProfile"
}

variable "agent_group" {
  description = "Sandcat agent group shown in CALDERA."
  type        = string
  default     = "red"
}

variable "ui_cidr" {
  description = "Open the CALDERA UI over HTTPS/443 (Caddy reverse-proxy) to this CIDR so a plain browser can reach it through 443-only firewalls — no client tooling needed. Set to a student's browser public IP (x.x.x.x/32), a campus CIDR, or 0.0.0.0/0 for a quick throwaway lab. Empty = closed (use SSM instead)."
  type        = string
  default     = ""
}

variable "rdp_cidr" {
  description = "Optional: open RDP (3389) on victims to this CIDR for GUI access. Empty = no RDP (use SSM)."
  type        = string
  default     = ""
}

variable "disable_realtime_protection" {
  description = "true = also try to turn off Defender real-time protection (Tamper Protection may block it). false = agent-path exclusions only."
  type        = bool
  default     = false
}
