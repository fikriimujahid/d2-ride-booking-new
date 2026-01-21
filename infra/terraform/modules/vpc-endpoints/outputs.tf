output "security_group_id" {
  description = "Security group attached to the interface endpoints"
  value       = aws_security_group.endpoints.id
}

output "ssm_endpoint_id" {
  description = "VPC endpoint ID for SSM"
  value       = aws_vpc_endpoint.ssm.id
}

output "ec2messages_endpoint_id" {
  description = "VPC endpoint ID for EC2 Messages"
  value       = aws_vpc_endpoint.ec2messages.id
}

output "ssmmessages_endpoint_id" {
  description = "VPC endpoint ID for SSM Messages"
  value       = aws_vpc_endpoint.ssmmessages.id
}
