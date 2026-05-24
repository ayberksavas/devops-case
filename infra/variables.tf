variable "region" {
  description = "AWS region where the EC2 lives."
  type        = string
  default     = "eu-north-1"
}

variable "instance_type" {
  description = "EC2 instance type. c7i-flex.large gives 2 vCPU / 4 GiB which fits free tier and minikube's 2 GiB floor."
  type        = string
  default     = "c7i-flex.large"
}

variable "ami_id" {
  description = "AMI ID of the running EC2 (Ubuntu 26.04 LTS amd64). No default — must be set in terraform.tfvars so plan shows no drift after import."
  type        = string
}

variable "ssh_allowed_cidr" {
  description = "CIDR allowed to SSH in (port 22). Should be your home /32 — never 0.0.0.0/0."
  type        = string
  sensitive   = true
}

variable "key_pair_name" {
  description = "EC2 key pair name used for SSH. Override if your key has a different name."
  type        = string
  default     = "devops-case"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 20
}

variable "ec2_instance_profile_name" {
  description = "Existing IAM instance profile attached to the EC2 (created manually in Day 3.4 for SSM). Not managed by this Terraform configuration."
  type        = string
  default     = "devops-case-ec2-ssm"
}

variable "project_tag" {
  description = "Value of the Project tag applied to all resources."
  type        = string
  default     = "devops-case"
}
