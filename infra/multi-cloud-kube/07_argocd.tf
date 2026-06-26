

# # ##############################
# # Argo CD: SA + binding
# # ##############################
# # SA
# resource "kubernetes_service_account" "argocd_manager" {
#   provider = kubernetes.aks
#   metadata {
#     name      = "argocd-manager"
#     namespace = "kube-system"
#   }
# }

# # Secret
# resource "kubernetes_secret" "argocd_manager_token" {
#   provider = kubernetes.aks
#   metadata {
#     name      = "argocd-manager-token"
#     namespace = "kube-system"
#     annotations = {
#       "kubernetes.io/service-account.name" = "argocd-manager"
#     }
#   }

#   type                           = "kubernetes.io/service-account-token"
#   wait_for_service_account_token = true
# }

# # Role binding
# resource "kubernetes_cluster_role_binding" "argocd_manager" {
#   provider = kubernetes.aks
#   metadata { name = "argocd-manager" }
#   role_ref {
#     api_group = "rbac.authorization.k8s.io"
#     kind      = "ClusterRole"
#     name      = "cluster-admin"
#   }
#   subject {
#     kind      = "ServiceAccount"
#     name      = "argocd-manager"
#     namespace = "kube-system"
#   }
# }


# # ##############################
# # ArgoCD: Cluster Secret
# # ##############################
# # AKS cluster
# resource "kubernetes_secret" "aks_cluster" {
#   provider = kubernetes.eks
#   metadata {
#     name      = "aks-cluster"
#     namespace = "argocd"
#     labels = {
#       "argocd.argoproj.io/secret-type" = "cluster"
#       cloud                            = "azure"
#       workload                         = "demo-api"
#     }
#   }

#   data = {
#     name   = "aks-cluster"
#     server = module.aks.cluster_endpoint
#     config = jsonencode({
#       bearerToken     = kubernetes_secret.argocd_manager_token.data["token"]
#       tlsClientConfig = { caData = module.aks.cluster_ca_certificate }
#     })
#   }
# }

# EKS cluster
resource "kubernetes_secret" "eks_cluster" {
  provider = kubernetes.eks
  metadata {
    name      = "eks-incluster"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
      cloud                            = "aws"
      workload                         = "demo-api"
    }
  }

  data = {
    name   = "eks-incluster"
    server = "https://kubernetes.default.svc"
    config = jsonencode({ tlsClientConfig = { insecure = false } })
  }
}


# ##############################
# Argo CD: Install
# ##############################
module "argocd" {
  source = "../../modules/aws/argocd"

  argocd_version = "9.7.0"

  depends_on = [module.eks_node_group_default]
}

# # ##############################
# # ArgoCD: App-of-apps
# # ##############################
# data "http" "argocd_root_app" {
#   url = "https://raw.githubusercontent.com/simonangel-fong/k8s-multi-cloud/refs/heads/master/argocd/00-root.yaml"
# }

# resource "kubernetes_manifest" "root" {
#   provider = kubernetes.eks
#   manifest = yamldecode(data.http.argocd_root_app.response_body)

#   depends_on = [module.argocd]
# }
