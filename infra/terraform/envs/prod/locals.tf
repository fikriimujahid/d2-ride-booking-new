locals {
  domain_base = "d2.${var.domain_name}"

  admin_domain     = "admin.${local.domain_base}"
  passenger_domain = "passenger.${local.domain_base}"
  driver_domain    = "driver.${local.domain_base}"
}
