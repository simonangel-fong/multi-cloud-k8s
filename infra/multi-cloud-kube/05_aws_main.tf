# main.tf

# ##############################
# VPC
# ##############################
module "vpc" {
  source = "../../modules/aws/vpc"

  vpc_name = local.common_name
  vpc_cidr = local.vpc_cidr
  vpc_tags = local.tags
}

# ##############################
# EKS
# ##############################
module "eks" {
  source = "../../modules/aws/eks"

  cluster_name    = local.common_name
  cluster_version = local.cluster_version
  subnet_ids      = module.vpc.private_subnet_ids
  cluster_tags    = local.tags
}

# ##############################
# EKS Node Group: default
# ##############################
module "eks_node_group_default" {
  source = "../../modules/aws/eks-node-group"

  cluster_name    = module.eks.cluster_name
  node_group_name = "default"
  subnet_ids      = module.vpc.private_subnet_ids

  instance_types = ["t3.medium"]
  capacity_type  = "ON_DEMAND"

  desired_size = 2
  min_size     = 1
  max_size     = 10

  tags = local.tags
}

# ##############################
# Argo CD
# ##############################
module "argocd" {
  source = "../../modules/aws/argocd"

  argocd_version = "9.7.0"

  depends_on = [module.eks_node_group_default]
}

# # ##############################
# # Argo CD: app-of-apps
# # ##############################
# data "http" "argocd_root_app" {
#   url = "https://raw.githubusercontent.com/simonangel-fong/k8s-multi-cloud/refs/heads/master/argocd/00-root.yaml"
# }

# resource "kubernetes_manifest" "argocd_root_app" {
#   manifest = yamldecode(data.http.argocd_root_app.response_body)

#   depends_on = [module.argocd]
# }
