# ##############################
# AKS: SA + binding
# ##############################
# SA
resource "kubernetes_service_account" "argocd_manager" {
  provider = kubernetes.aks
  metadata {
    name      = "argocd-manager"
    namespace = "kube-system"
  }
}

# Secret
resource "kubernetes_secret" "argocd_manager_token" {
  provider = kubernetes.aks
  metadata {
    name      = "argocd-manager-token"
    namespace = "kube-system"
    annotations = {
      "kubernetes.io/service-account.name" = "argocd-manager"
    }
  }

  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
}

# Role binding
resource "kubernetes_cluster_role_binding" "argocd_manager" {
  provider = kubernetes.aks
  metadata { name = "argocd-manager" }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "argocd-manager"
    namespace = "kube-system"
  }
}

# ##############################
# ArgoCD: Cluster Secret
# ##############################
# AKS cluster
resource "kubernetes_secret" "aks_cluster" {
  provider = kubernetes.eks
  metadata {
    name      = "aks-prod"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
      cloud                            = "azure"
      workload                         = "demo-api"
    }
  }

  data = {
    name   = "aks-prod"
    server = module.aks.cluster_endpoint
    config = jsonencode({
      bearerToken     = kubernetes_secret.argocd_manager_token.data["token"]
      tlsClientConfig = { caData = module.aks.cluster_ca_certificate }
    })
  }
}

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
# ArgoCD: App-of-apps
# ##############################
data "kubectl_path_documents" "root" {
  pattern = "${path.module}/../../argocd/00-root.yaml"
}

resource "kubectl_manifest" "root" {
  for_each  = toset(data.kubectl_path_documents.root.documents)
  yaml_body = each.value
}
