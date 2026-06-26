# Monitoring: Grafana Cloud for k8s-multi-cloud

Ship metrics, logs, and traces from `demo-api` in EKS and AKS to a single Grafana Cloud stack. Use Grafana Alloy in each cluster as the collection agent and view everything on one cross-cloud dashboard.

## Installation

| Env | Method                                                              |
| --- | ------------------------------------------------------------------- |
| dev | Grafana Cloud free stack; Alloy installed per-cluster via ArgoCD + Helm |

## Data flow

```txt
demo-api pod  ──/metrics──┐
                          ├──► Alloy (DaemonSet)  ──► Grafana Cloud  ──► Dashboard
kubelet/cAdvisor logs ────┘        (per cluster)       (Prom / Loki / Tempo)
```

| Signal  | Source on pod                | Alloy component       | Grafana Cloud backend |
| ------- | ---------------------------- | --------------------- | --------------------- |
| metrics | `/metrics` (Prometheus)      | `prometheus.scrape`   | Prometheus (Mimir)    |
| logs    | container stdout/stderr      | `loki.source.kubernetes` | Loki              |
| traces  | OTLP `4317` from app         | `otelcol.receiver.otlp` → `otelcol.exporter.otlphttp` | Tempo |

## Repo Layout

```
helm/multicloud-demo-api/
  values.yaml             # add: serviceMonitor / prom annotations, OTEL env, /metrics port
  values-aws.yaml         # cluster=aws label
  values-azure.yaml       # cluster=azure label
argocd/
  app/
    04-alloy.yaml         # ApplicationSet — Alloy DaemonSet per cluster
  alloy-config/
    values-aws.yaml       # external_labels: cluster=eks, cloud=aws
    values-azure.yaml     # external_labels: cluster=aks, cloud=azure
grafana/
  dashboards/
    multicloud-demo-api.json   # imported / exported from Grafana Cloud
```

> Grafana Cloud credentials (Prometheus / Loki / Tempo username + API token) are stored as a Kubernetes Secret per cluster, referenced by the Alloy chart via `extraEnvFrom`. The Secret is created out-of-band (CLI) for now; promote to External Secrets Operator later.

## Resources

| Resource              | Where                                       | Purpose                                                          |
| --------------------- | ------------------------------------------- | ---------------------------------------------------------------- |
| Grafana Cloud stack   | grafana.com                                 | Hosted Prom + Loki + Tempo + Grafana                             |
| `grafana-cloud` Secret | each cluster, `monitoring` ns               | `PROM_USER`, `PROM_PASS`, `LOKI_USER`, `LOKI_PASS`, `TEMPO_USER`, `TEMPO_PASS` |
| `alloy` DaemonSet     | each cluster, `monitoring` ns               | Scrapes pods, ships logs, forwards OTLP traces                   |
| ServiceMonitor / annotations | `demo-api` ns                       | Tells Alloy which pods to scrape (`prometheus.io/scrape: "true"`) |
| Dashboard             | Grafana Cloud → Dashboards                  | RED metrics + log panel split by `cloud_provider`                |

## Goals

- One Grafana Cloud stack, two clusters reporting in parallel
- All three signals (metric / log / trace) flowing for `demo-api`
- Dashboard panels can be split / filtered by `cloud=aws|azure`
- Alloy + its config managed declaratively via ArgoCD, same pattern as Envoy Gateway
- No app changes beyond instrumenting `demo-api` once

---

## Phases

| #   | Goal                          | Done when                                                                                                                                          |
| --- | ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| 00  | Grafana Cloud stack           | Free stack created; Prometheus / Loki / Tempo write endpoints + API tokens captured; `curl` smoke test against `/api/prom/push` returns 200/204    |
| 01  | Instrument `demo-api`         | `/metrics` endpoint serves Prom metrics (request count / latency); OTLP exporter env vars wired; `go build` + local `curl localhost:8080/metrics` works |
| 02  | Helm chart wiring             | `helm/multicloud-demo-api/values.yaml` exposes scrape annotations + OTEL env; rendered manifest has `prometheus.io/scrape: "true"` and OTLP env set |
| 03  | Grafana Cloud Secret per cluster | `kubectl -n monitoring get secret grafana-cloud` exists on both EKS and AKS with all six keys                                                  |
| 04  | Deploy Alloy via ArgoCD       | `04-alloy.yaml` ApplicationSet rolls out Alloy DaemonSet on both clusters; pods Ready; Alloy UI (`port-forward 12345`) shows healthy components     |
| 05  | Signals visible in Grafana Cloud | Explore → Prometheus shows `demo_api_*` series with `cloud` label for both clouds; Loki shows demo-api logs; Tempo shows traces with cluster tag |
| 06  | Cross-cloud dashboard         | `multicloud-demo-api.json` imported; one row shows AWS vs Azure side-by-side (RPS, p95 latency, error rate, log tail)                              |

---

## Out of Scope (this stage)

- Self-hosted Prometheus / Loki / Tempo
- Alerts / on-call routing / SLOs
- Long-term storage tuning, recording rules
- Secrets via External Secrets Operator (manual `kubectl create secret` for now)
- mTLS between Alloy and apps; cluster-internal scrape uses HTTP
- RUM / frontend telemetry

---

## Note

### Grafana Cloud (phase 00)

1. Sign up at https://grafana.com → create stack `k8s-multi-cloud-dev`.
2. From the stack page, capture for each backend:
   - **Prometheus**: `remote_write` URL (e.g. `https://prometheus-prod-XX-prod-ca-central-0.grafana.net/api/prom/push`), username (numeric instance id).
   - **Loki**: push URL, username.
   - **Tempo**: OTLP endpoint (`tempo-prod-XX-prod-ca-central-0.grafana.net:443`), username.
3. Create one **Access Policy** with scopes `metrics:write`, `logs:write`, `traces:write`. Generate one token, save as `GC_TOKEN`.

Smoke test the metrics endpoint:

```sh
curl -u "$GC_PROM_USER:$GC_TOKEN" \
  -X POST "$GC_PROM_URL" \
  -H "Content-Type: application/x-protobuf" \
  -H "Content-Encoding: snappy" \
  --data-binary @/dev/null
# expect HTTP 400 "no metrics" (auth ok) — 401/403 means token is wrong
```

### Instrument `demo-api` (phase 01)

Add to `app/demo-api/main.go`:

```go
import (
    "github.com/prometheus/client_golang/prometheus/promhttp"
)

// in main():
r.GET("/metrics", gin.WrapH(promhttp.Handler()))
```

Add request middleware that records `demo_api_requests_total{route,code}` and `demo_api_request_duration_seconds_bucket{route}`. For traces, set OTLP via env (read by the SDK at startup):

```sh
OTEL_SERVICE_NAME=demo-api
OTEL_EXPORTER_OTLP_ENDPOINT=http://alloy.monitoring.svc.cluster.local:4317
OTEL_RESOURCE_ATTRIBUTES=cloud_provider=$CLOUD_PROVIDER,service.version=$VERSION
```

Local verify:

```sh
cd app/demo-api && go run .
curl localhost:8080/api/   && curl -s localhost:8080/metrics | grep demo_api_requests_total
```

### Helm wiring (phase 02)

In `helm/multicloud-demo-api/values.yaml`:

```yaml
service:
  port: 80
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/metrics"

env:
  OTEL_SERVICE_NAME: demo-api
  OTEL_EXPORTER_OTLP_ENDPOINT: http://alloy.monitoring.svc.cluster.local:4317
  OTEL_RESOURCE_ATTRIBUTES: "service.version=0.1.0"
```

Per-cloud `values-aws.yaml` / `values-azure.yaml` add `CLOUD_PROVIDER` and a `cloud` pod label (`aws` / `azure`) so Alloy can attach it as an `external_label`.

### Grafana Cloud Secret (phase 03)

Run once per cluster (after `aws eks update-kubeconfig` / `az aks get-credentials`):

```sh
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

kubectl -n monitoring create secret generic grafana-cloud \
  --from-literal=PROM_URL="$GC_PROM_URL" \
  --from-literal=PROM_USER="$GC_PROM_USER" \
  --from-literal=PROM_PASS="$GC_TOKEN" \
  --from-literal=LOKI_URL="$GC_LOKI_URL" \
  --from-literal=LOKI_USER="$GC_LOKI_USER" \
  --from-literal=LOKI_PASS="$GC_TOKEN" \
  --from-literal=TEMPO_URL="$GC_TEMPO_URL" \
  --from-literal=TEMPO_USER="$GC_TEMPO_USER" \
  --from-literal=TEMPO_PASS="$GC_TOKEN"
```

### Deploy Alloy via ArgoCD (phase 04)

`argocd/app/04-alloy.yaml` — ApplicationSet, same `workload=demo-api` cluster selector as the existing apps:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: alloy
  namespace: argocd
spec:
  goTemplate: true
  generators:
    - clusters:
        selector:
          matchLabels:
            workload: demo-api
  template:
    metadata:
      name: '{{ .name }}-04-alloy'
      annotations:
        argocd.argoproj.io/sync-wave: "3"
    spec:
      project: platform-system
      source:
        repoURL: https://grafana.github.io/helm-charts
        chart: alloy
        targetRevision: 0.x.x   # pin actual version
        helm:
          valueFiles:
            - $values/argocd/alloy-config/values-{{ index .metadata.labels "cloud" }}.yaml
      destination:
        server: '{{ .server }}'
        namespace: monitoring
      syncPolicy:
        automated: { prune: true, selfHeal: true }
        syncOptions: [CreateNamespace=true, ServerSideApply=true]
```

`argocd/alloy-config/values-aws.yaml` contains the Alloy River config that:

- Scrapes pods with `prometheus.io/scrape: "true"` and remote-writes to Grafana Cloud Prom with `external_labels: { cluster: eks, cloud: aws }`.
- Tails container logs and ships to Loki with the same labels.
- Receives OTLP gRPC on `:4317` and forwards to Tempo.

Verify:

```sh
kubectl -n monitoring get pods -l app.kubernetes.io/name=alloy
# alloy-xxxxx   1/1 Running   (one per node)
kubectl -n monitoring port-forward svc/alloy 12345:12345
# browse http://localhost:12345 → all components green
```

### Visible in Grafana Cloud (phase 05)

In Grafana Cloud → Explore:

- **Prometheus**: `sum by (cloud) (rate(demo_api_requests_total[5m]))` — two series, `aws` and `azure`.
- **Loki**: `{namespace="demo-api"} | json | line_format "{{.cloud}} {{.msg}}"`.
- **Tempo**: search `service.name=demo-api`, expect spans tagged with `cloud_provider`.

### Dashboard (phase 06)

Build once in Grafana Cloud, then export JSON to `grafana/dashboards/multicloud-demo-api.json`:

| Row              | Panels                                                                              |
| ---------------- | ----------------------------------------------------------------------------------- |
| Overview         | RPS, error %, p95 latency — all split by `cloud`                                    |
| AWS vs Azure     | Two stat panels side-by-side: live `cloud_provider` traffic share (mirrors the CF demo) |
| Logs             | Loki tail of `{namespace="demo-api"}`, filter dropdown for `cloud`                  |
| Traces           | Tempo trace list, links from a slow-request log line                                |

Re-import later with the Grafana Cloud "Import dashboard" UI or via Terraform / `grafana-operator` (out of scope for this phase).

---

## Runbook

```sh
# Force Alloy to reload config after a values change
kubectl -n monitoring rollout restart ds/alloy

# Check what Alloy is actually scraping
kubectl -n monitoring port-forward ds/alloy 12345:12345
# http://localhost:12345/graph

# Confirm a metric reached Grafana Cloud
curl -u "$GC_PROM_USER:$GC_TOKEN" \
  "$GC_PROM_QUERY_URL/api/v1/query?query=up{job=\"demo-api\"}"
```
