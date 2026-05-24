# Default VPC + subnets already exist in the account (AWS auto-creates one per
# region). We reference, never create — this configuration is scoped to
# EC2/EIP/SG only, per the case-study brief.
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ---- Security group --------------------------------------------------------
#
# Inline ingress/egress rules instead of separate aws_vpc_security_group_*_rule
# resources. The newer separate-resource pattern is recommended for SGs whose
# rules change often (avoids whole-SG recreation on a single rule edit), but
# for a static demo SG with four documented rules, inline keeps the import
# story simple (one SG = one import) and puts all the rules in one block for
# easy code review.

resource "aws_security_group" "minikube" {
  # Auto-named by the EC2 launch wizard on Day 0 ("launch-wizard-3").
  # Renaming this would force a destroy/recreate of the SG, which means
  # detaching from the running EC2 — risky on a live host. Matched to live.
  name = "launch-wizard-3"

  # Description is set by the launch wizard at creation time and is immutable
  # in AWS (can't be changed without recreating the SG). lifecycle.ignore_changes
  # below tells Terraform to skip the comparison, so plan stays clean regardless
  # of what the live string is.
  description = "Managed: original description set by EC2 launch wizard"

  vpc_id = data.aws_vpc.default.id

  ingress {
    description = "SSH from home"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  ingress {
    description = "HTTP - public ingress to minikube"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS - public ingress to minikube"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "NodePort range - minikube exposes services here"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project = var.project_tag
    Name    = "devops-case-sg"
  }

  lifecycle {
    # Description is immutable in AWS — skip to keep plan empty.
    # Tags listed too so plan stays clean if the live SG isn't tagged yet;
    # remove the `tags` line below to enforce them via apply.
    ignore_changes = [description, tags, tags_all]
  }
}

# ---- EC2 instance ----------------------------------------------------------

resource "aws_instance" "minikube" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.minikube.id]

  # Existing instance profile, created manually in Day 3.4 for the SSM agent.
  # Not managed by this configuration — referenced by name only.
  iam_instance_profile = var.ec2_instance_profile_name

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
  }

  tags = {
    Project = var.project_tag
    Name    = "devops-case"
  }

  # Don't recreate the instance if `var.ami_id` ever drifts from the live AMI.
  # We're tracking an already-running host; an apply that re-launches it would
  # destroy minikube state, the /opt/devops-case checkout, and the SSM-managed
  # auto-deploy plumbing. Safer to require explicit human action for AMI changes.
  lifecycle {
    ignore_changes = [ami]
  }
}

# ---- Elastic IP ------------------------------------------------------------
#
# Association via the EIP's network_interface attribute, not a separate
# aws_eip_association resource. The aws_eip_association resource has a known
# regression in the modern AWS provider — it rejects VPC EIPs at import time
# with "with the retirement of EC2-Classic standard domain EC2 EIPs are no
# longer supported". The fix is to bind the EIP to the instance's primary
# ENI directly here.

resource "aws_eip" "minikube" {
  domain            = "vpc"
  network_interface = aws_instance.minikube.primary_network_interface_id

  tags = {
    Project = var.project_tag
    Name    = "devops-case-eip"
  }
}
