output "instance_id" {
  description = "Bastion instance ID"
  value       = aws_instance.bastion.id
}

output "public_ip" {
  description = "Bastion public IP"
  value       = aws_instance.bastion.public_ip
}

output "private_ip" {
  description = "Bastion private IP"
  value       = aws_instance.bastion.private_ip
}

output "security_group_id" {
  description = "Bastion security group ID"
  value       = aws_security_group.bastion.id
}

output "instance_profile_name" {
  description = "Bastion instance profile name"
  value       = aws_iam_instance_profile.bastion.name
}
