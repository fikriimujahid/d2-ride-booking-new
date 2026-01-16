aws_region          = "ap-southeast-1"
availability_zone   = "ap-southeast-1a"
vpc_cidr            = "10.20.0.0/16"
public_subnet_cidr  = "10.20.1.0/24"
private_subnet_cidr = "10.20.11.0/24"

# Cost toggle: keep NAT off by default
enable_nat_gateway = false

tags = {
  Environment = "dev"
  Project     = "ride-booking-demo"
  ManagedBy   = "terraform"
}
