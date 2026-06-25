# main.tf

# ##############################
# Resource Group
# ##############################
resource "azurerm_resource_group" "main" {
  name     = local.common_name
  location = var.az_location
  tags     = local.tags
}

# ##############################
# AKS
# ##############################
module "aks" {
  source = "../../modules/az/aks"

  # ####################
  # Resource Group
  # ####################
  rg_name     = azurerm_resource_group.main.name
  rg_location = azurerm_resource_group.main.location
  tags        = local.tags

  # ####################
  # Networking
  # ####################
  vnet_cidr = local.vnet_cidr

  # ####################
  # AKS
  # ####################
  cluster_version = local.cluster_version
  default_node_pool = {
    vm_size      = "standard_dc2s_v3"
    node_count   = 1
    min_count    = 1
    max_count    = 3
    auto_scaling = true
  }
}
