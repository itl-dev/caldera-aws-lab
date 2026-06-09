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
  description = "Optional: open CALDERA UI (8888) directly to this CIDR. Normally leave empty and view the UI via SSM port forwarding (works through restrictive firewalls)."
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
