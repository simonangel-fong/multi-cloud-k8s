# outputs.tf

output "cluster_name" { value = azurerm_kubernetes_cluster.this.name }
output "cluster_id" { value = azurerm_kubernetes_cluster.this.id }
output "cluster_version" { value = azurerm_kubernetes_cluster.this.kubernetes_version }
output "cluster_endpoint" { value = azurerm_kubernetes_cluster.this.kube_config[0].host }
output "cluster_ca_certificate" {
  value     = azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate
  sensitive = true
}
output "kube_config_raw" {
  value     = azurerm_kubernetes_cluster.this.kube_config_raw
  sensitive = true
}
output "oidc_issuer_url" { value = azurerm_kubernetes_cluster.this.oidc_issuer_url }
output "node_resource_group" { value = azurerm_kubernetes_cluster.this.node_resource_group }
