# ----------------------------------------------------------------------------
# VPC ID
# ----------------------------------------------------------------------------
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

# ----------------------------------------------------------------------------
# PUBLIC SUBNET ID
# ----------------------------------------------------------------------------
output "public_subnet_id" {
  description = "Public subnet ID"

  # value: The ID of the public subnet resource
  value = aws_subnet.public.id
}

# Optional secondary public subnet ID for multi-AZ ALB.
output "public_subnet_id_secondary" {
  description = "Secondary public subnet ID (null when not created)"
  value       = try(aws_subnet.public_secondary[0].id, null)
}

output "public_subnet_ids" {
  description = "List of public subnet IDs (primary + optional secondary)"
  value = compact([
    aws_subnet.public.id,
    try(aws_subnet.public_secondary[0].id, null)
  ])
}

# ----------------------------------------------------------------------------
# PRIVATE SUBNET ID
# ----------------------------------------------------------------------------
output "private_subnet_id" {
  description = "Private subnet ID"

  # value: The ID of the private subnet resource
  value = aws_subnet.private.id
}

# ----------------------------------------------------------------------------
# PRIVATE SUBNET IDS (LIST)
# ----------------------------------------------------------------------------
output "private_subnet_ids" {
  description = "List of private subnet IDs (includes secondary if configured)"
  value = compact([
    aws_subnet.private.id,
    try(aws_subnet.private_secondary[0].id, null)
  ])
}

# ----------------------------------------------------------------------------
# PRIVATE APP SUBNET IDS (LIST)
# ----------------------------------------------------------------------------
# Backward-compatible alias for the module's historical "private" subnet tier.
output "private_app_subnet_ids" {
  description = "List of private app subnet IDs (alias of private_subnet_ids for backward compatibility)"
  value = compact([
    aws_subnet.private.id,
    try(aws_subnet.private_secondary[0].id, null)
  ])
}

# ----------------------------------------------------------------------------
# PRIVATE DB SUBNET IDS (LIST) - OPTIONAL
# ----------------------------------------------------------------------------
output "private_db_subnet_ids" {
  description = "List of private DB subnet IDs (empty when not configured)"
  value = compact([
    try(aws_subnet.private_db[0].id, null),
    try(aws_subnet.private_db_secondary[0].id, null)
  ])
}

# ----------------------------------------------------------------------------
# INTERNET GATEWAY ID
# ----------------------------------------------------------------------------
output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = aws_internet_gateway.this.id
}

# ----------------------------------------------------------------------------
# NAT GATEWAY ID
# ----------------------------------------------------------------------------
output "nat_gateway_id" {
  description = "NAT Gateway ID (null when disabled)"

  # value: Try to get NAT Gateway ID, return null if it doesn't exist
  #
  # EXPLANATION OF THE SYNTAX:
  # - aws_nat_gateway.this is a list (because we used count)
  # - [0] gets the first (and only) item from the list
  # - .id gets the ID attribute
  # - If the list is empty (count = 0), try() catches the error and returns null
  value = try(aws_nat_gateway.this[0].id, null)
}

# ----------------------------------------------------------------------------
# PUBLIC ROUTE TABLE ID
# ----------------------------------------------------------------------------
output "public_route_table_id" {
  description = "Public route table ID"
  value       = aws_route_table.public.id
}

# ----------------------------------------------------------------------------
# PRIVATE ROUTE TABLE ID
# ----------------------------------------------------------------------------
output "private_route_table_id" {
  description = "Private route table ID"
  value       = aws_route_table.private.id
}