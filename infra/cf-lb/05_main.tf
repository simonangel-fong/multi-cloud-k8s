# main.tf

# ##############################
# Zone lookup
# ##############################
data "cloudflare_zone" "zone" {
  filter = {
    name = var.cf_zone_name
  }
}

# ##############################
# Health monitor
# ##############################
resource "cloudflare_load_balancer_monitor" "http" {
  account_id       = var.cf_account_id
  type             = "http"
  description      = "${local.common_name} HTTP monitor for ${local.fqdn}"
  method           = "GET"
  path             = "/api/"
  port             = 80
  expected_codes   = "200"
  follow_redirects = false
  allow_insecure   = false
  interval         = 60
  retries          = 2
  timeout          = 5

  header = {
    Host = [local.fqdn]
  }
}

# ##############################
# Origin pools
# ##############################
resource "cloudflare_load_balancer_pool" "aws" {
  account_id = var.cf_account_id
  name       = "${local.common_name}-aws"
  enabled    = true
  monitor    = cloudflare_load_balancer_monitor.http.id

  origins = [{
    name    = "eks-envoy-gateway"
    address = var.aws_origin_address
    enabled = true
    weight  = 1
  }]
}

resource "cloudflare_load_balancer_pool" "azure" {
  account_id = var.cf_account_id
  name       = "${local.common_name}-azure"
  enabled    = true
  monitor    = cloudflare_load_balancer_monitor.http.id

  origins = [{
    name    = "aks-envoy-gateway"
    address = var.azure_origin_address
    enabled = true
    weight  = 1
  }]
}
