# outputs.tf

# ##############################
# Cloudflare
# ##############################
output "cf_zone_name" {
  description = "Cloudflare zone name"
  value       = data.cloudflare_zone.zone.name
}

output "cf_monitor_id" {
  description = "Cloudflare LB monitor id"
  value       = cloudflare_load_balancer_monitor.http.id
}

output "cf_pool_aws_id" {
  description = "Cloudflare LB pool id (AWS/EKS)"
  value       = cloudflare_load_balancer_pool.aws.id
}

output "cf_pool_azure_id" {
  description = "Cloudflare LB pool id (Azure/AKS)"
  value       = cloudflare_load_balancer_pool.azure.id
}

output "cf_lb_id" {
  description = "Cloudflare load balancer id"
  value       = cloudflare_load_balancer.cloud.id
}

output "cf_hostname" {
  description = "Public hostname fronting both clouds"
  value       = local.fqdn
}
