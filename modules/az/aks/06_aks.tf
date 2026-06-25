# # main.tf

# ##############################
# AKS Cluster
# ##############################
resource "azurerm_kubernetes_cluster" "this" {
  name                = local.common_name
  location            = var.rg_location
  resource_group_name = var.rg_name

  kubernetes_version = var.cluster_version


  # ####################
  # identity
  # ####################
  identity {
    type = "SystemAssigned"
  }
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # ####################
  # default (system) node pool
  # ####################
  default_node_pool {
    name                 = "system"
    vnet_subnet_id       = azurerm_subnet.this.id
    vm_size              = var.default_node_pool.vm_size
    node_count           = var.default_node_pool.node_count
    auto_scaling_enabled = var.default_node_pool.auto_scaling
    min_count            = var.default_node_pool.auto_scaling ? var.default_node_pool.min_count : null
    max_count            = var.default_node_pool.auto_scaling ? var.default_node_pool.max_count : null
  }

  # ####################
  # networking
  # ####################
  dns_prefix = local.common_name
  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
  }

  tags = merge(
    var.tags,
    { Name = local.common_name }
  )
}
