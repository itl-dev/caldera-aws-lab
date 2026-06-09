###############################################################################
# CALDERA lab on AWS Academy Learner Lab — single stack
#   - 1x CALDERA server (Ubuntu 22.04)
#   - N x victim Windows (Win Server 2022) with the sandcat agent auto-deployed
# One `terraform apply` brings up everything; victims auto-point at the server's
# private IP, so there is no IP to copy by hand.
###############################################################################

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_vpc" "default" {
  default = true
}

# Amazon-published AMIs (Quick Start) — allowed in Learner Lab (Marketplace AMIs are not)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_ami" "win2022" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

###############################################################################
# Security groups
#   UI/shell access is via SSM (HTTPS 443), so NO public inbound is required.
#   Server only needs the agent contact ports reachable from inside the VPC.
#   Victim RDP is opt-in (set rdp_cidr) for those who want the GUI.
###############################################################################
resource "aws_security_group" "server" {
  name_prefix = "caldera-server-"
  description = "CALDERA server: agent contacts from within the VPC; egress all. UI via SSM."

  ingress {
    description = "sandcat HTTP contact (8888) from victims in the VPC"
    from_port   = 8888
    to_port     = 8888
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }
  ingress {
    description = "Other agent contacts (TCP/websocket) from within the VPC"
    from_port   = 7010
    to_port     = 7012
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }
  # Optional: expose the UI publicly to a single IP (normally unnecessary — use SSM).
  dynamic "ingress" {
    for_each = var.ui_cidr == "" ? [] : [var.ui_cidr]
    content {
      description = "CALDERA UI direct (optional)"
      from_port   = 8888
      to_port     = 8888
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "caldera-server" }
}

resource "aws_security_group" "victim" {
  name_prefix = "caldera-victim-"
  description = "CALDERA victim: agent beacons outbound; optional RDP. Shell via SSM."

  dynamic "ingress" {
    for_each = var.rdp_cidr == "" ? [] : [var.rdp_cidr]
    content {
      description = "RDP (optional)"
      from_port   = 3389
      to_port     = 3389
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "caldera-victim" }
}

###############################################################################
# CALDERA server
###############################################################################
resource "aws_instance" "server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.server_instance_type
  key_name               = var.key_name
  iam_instance_profile   = var.instance_profile # SSM Session Manager
  vpc_security_group_ids = [aws_security_group.server.id]
  user_data              = file("${path.module}/userdata-server.sh")

  root_block_device {
    volume_size = 30 # node_modules + Go build need headroom (<=100GB, gp3 allowed)
    volume_type = "gp3"
  }

  tags = { Name = "caldera-server" }
}

###############################################################################
# Victim Windows host(s) — auto-deploys the sandcat agent on first boot,
# pointing at the server's PRIVATE IP (traffic stays inside the VPC).
###############################################################################
resource "aws_instance" "victim" {
  count                  = var.victim_count
  ami                    = data.aws_ami.win2022.id
  instance_type          = var.victim_instance_type
  key_name               = var.key_name
  iam_instance_profile   = var.instance_profile
  vpc_security_group_ids = [aws_security_group.victim.id]
  get_password_data      = true

  user_data = templatefile("${path.module}/userdata-victim.ps1.tpl", {
    caldera_server = "http://${aws_instance.server.private_ip}:8888"
    agent_group    = var.agent_group
    disable_rtp    = var.disable_realtime_protection
  })

  tags = { Name = "caldera-victim-${count.index + 1}" }
}
