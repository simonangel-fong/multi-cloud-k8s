# Cloudflare LB: multi-cloud entry point for k8s-multi-cloud

Use Cloudflare Load Balancing to front the EKS and AKS Envoy Gateway public LBs behind a single hostname (`cloud.arguswatcher.net`) with health-checked failover.

## Installation

| Env | Method                                        |
| --- | --------------------------------------------- |
| dev | Cloudflare zone `arguswatcher.net`, Terraform |

## Repo Layout

```
infra/cf-lb/
  01_variables.tf   # project_name, env, zone, hostname, origin endpoints
  02_locals.tf      # common_name, naming
  03_providers.tf   # cloudflare provider + s3 backend
  04_outputs.tf     # final hostname, LB id, pool ids
  05_main.tf        # monitor + pools + load balancer + DNS record
  backend.hcl       # shared bucket; key=multi-cloud-k8s/cloudflare/terraform.tfstate
```

> Origin endpoints (EKS ELB hostname, AKS LB IP) come from the Envoy Gateway `gateway.status.addresses[0].value` in each cluster — see [argocd.md](argocd.md). Wired into `cf-lb` via `tfvars` for now; promote to cross-stack `terraform_remote_state` once stable.

## Resources

| Resource       | Cloudflare type                    | Purpose                                                   |
| -------------- | ---------------------------------- | --------------------------------------------------------- |
| `monitor-http` | `cloudflare_load_balancer_monitor` | HTTP probe on `/api/` with `Host: cloud.arguswatcher.net` |
| `pool-aws`     | `cloudflare_load_balancer_pool`    | Origin = EKS Envoy Gateway ELB hostname                   |
| `pool-azure`   | `cloudflare_load_balancer_pool`    | Origin = AKS Envoy Gateway LB IP                          |
| `lb-cloud`     | `cloudflare_load_balancer`         | Steering = `random`; both pools as default                |
| `record-cloud` | `cloudflare_record` (proxied)      | `cloud.arguswatcher.net` → LB, TLS at edge                |

## Steering

`random` across both pools. Cloudflare picks an available pool per request; unhealthy pools drop out automatically via the monitor. No geo affinity in this phase.

## TLS

Edge-terminated by Cloudflare (proxied = `true`). Origins stay HTTP on port 80 — the Envoy Gateway listener in [argocd/envoy-gateway-config/gateway.yaml](../argocd/envoy-gateway-config/gateway.yaml) does not yet terminate TLS. Cloudflare → origin uses "Flexible" SSL initially; upgrade to "Full" once origins have certs.

## Goals

- Single public hostname for both clouds
- Active/active with health-based failover
- TLS terminated at Cloudflare edge
- All resources declarative in `infra/cf-lb`, state in the same S3 bucket as `multi-cloud-kube`

---

## Phases

| #   | Goal                       | Done when                                                                                                                                  |
| --- | -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| 00  | Scaffold + backend         | `terraform -chdir=infra/cf-lb init -backend-config=backend.hcl` succeeds; state object at `multi-cloud-k8s/cloudflare/terraform.tfstate`   |
| 01  | Provider + zone wiring     | `cloudflare` provider authenticated via `CLOUDFLARE_API_TOKEN`; `data "cloudflare_zone"` for `arguswatcher.net` returns a zone id          |
| 02  | Health monitor             | Monitor created; `cloudflare_load_balancer_monitor` shows healthy probes against both origins                                              |
| 03  | Origin pools (AWS + Azure) | Both pools `healthy` in CF dashboard; origins resolve to current Envoy Gateway LB endpoints                                                |
| 04  | Load balancer + DNS record | `dig cloud.arguswatcher.net` returns CF anycast IPs; `curl https://cloud.arguswatcher.net/api/` returns 200                                |
| 05  | Failover validation        | Scale one cloud's Envoy Gateway to 0; monitor flips that pool unhealthy; traffic shifts to the other cloud; `cloud_provider` in JSON flips |

---

## Out of Scope (this stage)

- Geo / latency steering policies
- WAF, rate limiting, bot management
- Cloudflare Access / Zero Trust
- mTLS or Full (Strict) origin TLS
- Per-path routing across pools

---

## Note

### Inputs

Set in `infra/cf-lb/terraform.tfvars`:

```hcl
env                  = "dev"
cf_zone_name         = "arguswatcher.net"
hostname             = "cloud"
aws_origin_hostname  = "<eks-envoy-gateway-elb-hostname>"   # from kubectl get gateway eg -n envoy-gateway-system
azure_origin_address = "<aks-envoy-gateway-ip>"
```

Auth via env var:

```sh
export CLOUDFLARE_API_TOKEN=...   # scoped: Zone:Read, DNS:Edit, Load Balancing:Edit on arguswatcher.net
```

### Resolve origin endpoints

```sh
# EKS
aws eks update-kubeconfig --region ca-central-1 --name multi-cloud-k8s-dev
kubectl get gateway eg -n envoy-gateway-system -o jsonpath='{.status.addresses[0].value}'

# AKS
az aks get-credentials --resource-group multi-cloud-k8s-dev --name multi-cloud-k8s-dev --overwrite-existing
kubectl get gateway eg -n envoy-gateway-system -o jsonpath='{.status.addresses[0].value}'
# 20.48.140.60
```

### Provision

```sh
terraform -chdir=infra/cf-lb init -backend-config=backend.hcl -reconfigure
terraform -chdir=infra/cf-lb fmt && terraform -chdir=infra/cf-lb validate
terraform -chdir=infra/cf-lb plan
terraform -chdir=infra/cf-lb apply -auto-approve

terraform -chdir=infra/cf-lb destroy -auto-approve
```

### Verify

```sh
dig +short cloud.arguswatcher.net
# <Cloudflare anycast IPs>

# Repeat — random steering should return both clouds over time
for i in $(seq 1 10); do
  curl -s https://cloud.arguswatcher.net/api/ | jq -r .cloud_provider
done
# aws
# azure
# aws
# azure
# ...
```

### Failover drill

```sh
# Take AWS out of rotation
kubectl --context multi-cloud-k8s-dev -n envoy-gateway-system scale deploy envoy-envoy-gateway-system-eg-<hash> --replicas=0

# Within monitor interval, all requests should return azure
for i in $(seq 1 10); do
  curl -s https://cloud.arguswatcher.net/api/ | jq -r .cloud_provider
done
# azure
# azure
# ...

# Restore
kubectl --context multi-cloud-k8s-dev -n envoy-gateway-system scale deploy envoy-envoy-gateway-system-eg-<hash> --replicas=1
```

---

## Backend

Shared S3 bucket with `multi-cloud-kube`; distinct key:

```hcl
# infra/cf-lb/backend.hcl
bucket       = "<same bucket as multi-cloud-kube>"
key          = "multi-cloud-k8s/cloudflare/terraform.tfstate"
region       = "<same region>"
use_lockfile = true
encrypt      = true
```

```sh
TF_VAR_cf_api_token=
curl -H "Authorization: Bearer $TF_VAR_cf_api_token" "https://api.cloudflare.com/client/v4/user/tokens/verify"

# confirm account id
curl -s -H "Authorization: Bearer $TF_VAR_cf_api_token" https://api.cloudflare.com/client/v4/accounts

# confirm permision: load balancer
curl -s -H "Authorization: Bearer $TF_VAR_cf_api_token" https://api.cloudflare.com/client/v4/accounts/<account_id>/load_balancers/monitors

# confirm dns zone
curl -s -H "Authorization: Bearer $TF_VAR_cf_api_token" "https://api.cloudflare.com/client/v4/zones?name=arguswatcher.net"
```

```sh
# Both pools should report healthy origins
curl -s -H "Authorization: Bearer $TF_VAR_cf_api_token" \
  "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/load_balancers/pools/$(terraform -chdir=infra/cf-lb output -raw cf_pool_aws_id)/health"

curl -s -H "Authorization: Bearer $TF_VAR_cf_api_token" \
  "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/load_balancers/pools/$(terraform -chdir=infra/cf-lb output -raw cf_pool_azure_id)/health"


curl -v -H "Host: cloud.arguswatcher.net" "http://20.200.88.217/api/"
curl -v -H "Host: cloud.arguswatcher.net" "http://a4e79dabf1d6b41919543e2410b20307-31536122.ca-central-1.elb.amazonaws.com/api/"
```