# providers.tf

# ##############################
# Version
# ##############################
terraform {
  required_version = ">= v1.15.2"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }

  backend "s3" {}
}

# ##############################
# Providers - Cloudflare
# ##############################
provider "cloudflare" {
  api_token = var.cf_api_token
}
