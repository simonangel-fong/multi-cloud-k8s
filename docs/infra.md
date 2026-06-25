## Provision Infra

```sh
terraform -chdir=infra/multi-cloud-kube providers
terraform -chdir=infra/multi-cloud-kube init -backend-config=backend.hcl -reconfigure
terraform -chdir=infra/multi-cloud-kube fmt && terraform -chdir=infra/multi-cloud-kube validate
terraform -chdir=infra/multi-cloud-kube plan
terraform -chdir=infra/multi-cloud-kube apply -auto-approve

terraform -chdir=infra/aws destroy -auto-approve


```

---

## Networking - Design

### VPC

- `VPC` cidr range must be between
  - `/16` (65,536 IP addresses)
  - `/28` (16 IP addresses)
- VPC CIDR: `10.0.0.0/16`

| Subnet  | AZ            | CIDR          | Usable IPs |
| ------- | ------------- | ------------- | ---------- |
| public  | ca-central-1a | 10.0.0.0/24   | 251        |
| public  | ca-central-1b | 10.0.1.0/24   | 251        |
| private | ca-central-1a | 10.0.64.0/18  | 16,379     |
| private | ca-central-1b | 10.0.128.0/18 | 16,379     |
| private | ca-central-1d | 10.0.192.0/18 | 16,379     |

---

### VNet

- `virtual networks` and `subnets` cidr range must be between
  - `/2` (4,194,304 IP addresses)
  - `/29` (8 IP addresses)

---

## Cluster

```sh
# eks kubeconfig
aws eks update-kubeconfig --region ca-central-1 --name multi-cloud-k8s-dev

# aks kubeconfig
az aks get-credentials --resource-group multi-cloud-k8s-dev --name multi-cloud-k8s-dev --overwrite-existing

kubectl get nodes
```

---

## ArgoCD

```sh
argocd login localhost:8081 --username admin   --insecure
argocd cluster add multi-cloud-k8s-dev --name aks-dev --label cloud=azure --label workload=demo-api -y

argocd cluster list


kubectl apply -f argocd/00-root.yaml
```
