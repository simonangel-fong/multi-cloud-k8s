locals {

  # ##############################
  # Metadata
  # ##############################
  common_name = "${var.project_name}-${var.env}"
  fqdn        = "${var.hostname}.${var.cf_zone_name}"

  # ##############################
  # AWS
  # ##############################
  tags = {
    Project     = var.project_name
    Environment = var.env
    ManagedBy   = "terraform"
  }

}
