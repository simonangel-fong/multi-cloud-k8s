# outputs.tf

# ##############################
# Kubeconfig
# ##############################
output "kubeconfig_eks" {
  description = "Update local kubeconfig with EKS"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "kubeconfig_aks" {
  description = "Update local kubeconfig with AKS"
  value       = "az aks get-credentials --resource-group ${module.eks.cluster_name} --name ${module.eks.cluster_name} --overwrite-existing"
}

# ##############################
# Argocd
# ##############################
output "argocd_init_secret" {
  value = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
}

output "argocd_port_forward" {
  value = "kubectl -n argocd port-forward svc/argocd-server 8080:80"
}
