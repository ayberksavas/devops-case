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
  name        = "devops-case-sg"
  description = "Allow SSH from home + HTTP/HTTPS + minikube NodePort range"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH from home"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  ingress {
    description = "HTTP — public ingress to minikube"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS — public ingress to minikube"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "NodePort range — minikube exposes services here"
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
    Name    = "devops-case-minikube"
  }

  # Don't recreate the instance if `var.ami_id` ever drifts from the live AMI.
  # We're tracking an already-running host; an apply that re-launches it would
  # destroy minikube state, the /opt/devops-case checkout, and the SSM-managed
  # auto-deploy plumbing. Safer to require explicit human action for AMI changes.
  lifecycle {
    ignore_changes = [ami]
  }
}

# ---- Elastic IP + association ----------------------------------------------

resource "aws_eip" "minikube" {
  domain = "vpc"

  tags = {
    Project = var.project_tag
    Name    = "devops-case-eip"
  }
}

resource "aws_eip_association" "minikube" {
  instance_id   = aws_instance.minikube.id
  allocation_id = aws_eip.minikube.id
}
