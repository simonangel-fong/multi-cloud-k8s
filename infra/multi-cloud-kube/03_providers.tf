# providers.tf

# ##############################
# Version
# ##############################
terraform {
  required_version = ">= v1.15.2"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }

  backend "s3" {}
}

# ##############################
# Providers - AWS
# ##############################
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}

# EKS auth
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

# EKS kubernetes
provider "kubernetes" {
  alias                  = "eks"
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

# EKS helm
provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

# ##############################
# Providers - Azure
# ##############################
provider "azurerm" {
  features {}
}

provider "kubernetes" {
  alias                  = "aks"
  host                   = module.aks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.aks.cluster_ca_certificate)
  client_certificate     = base64decode(yamldecode(module.aks.kube_config_raw).users[0].user["client-certificate-data"])
  client_key             = base64decode(yamldecode(module.aks.kube_config_raw).users[0].user["client-key-data"])
}



