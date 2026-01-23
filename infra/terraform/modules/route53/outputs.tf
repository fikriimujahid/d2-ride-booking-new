output "admin_fqdn" {
  value       = "admin.${var.domain_name}"
  description = "Admin domain"
}

output "passenger_fqdn" {
  value       = "passenger.${var.domain_name}"
  description = "Passenger domain"
}

output "driver_fqdn" {
  value       = "driver.${var.domain_name}"
  description = "Driver domain (only created when alb_* provided)"
}
