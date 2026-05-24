output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.minikube.id
}

output "public_ip" {
  description = "Elastic IP attached to the EC2 instance. SSH and ingress traffic land here."
  value       = aws_eip.minikube.public_ip
}

output "security_group_id" {
  description = "Security group ID protecting the EC2."
  value       = aws_security_group.minikube.id
}
