# devops-case — InsiderOne DevOps Internship Case Study 2026

A small HTTP service shipped end-to-end like production: container → Kubernetes (Helm) → CI/CD → observability → public URL.

## Track

**Track A — Minikube on EC2.** See [`SETUP.md`](./SETUP.md) for the full infra setup log (EC2 type, security group, software install).

## The service

A minimal Flask service exposing three endpoints:

| Method | Path | Returns |
|--------|------|---------|
| GET | `/ping` | `pong` (text/plain) |
| GET | `/healthz` | `{"status":"ok"}` — used by Kubernetes probes |
| GET | `/version` | `{"sha":"<BUILD_SHA>"}` — the SHA the image was built from |

### Environment variables

See [`.env.example`](./.env.example).

| Variable | Default | Purpose |
|----------|---------|---------|
| `PORT` | `8080` | Port the service listens on |
| `BUILD_SHA` | `dev` | Returned by `/version`; set to the git commit SHA at image build time |

## Running locally

### Option 1 — Python directly

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python app.py
```

### Option 2 — Docker

```bash
docker build -t devops-case-app:local .
docker run --rm -p 8080:8080 -e BUILD_SHA=$(git rev-parse --short HEAD) devops-case-app:local
```

### Option 3 — docker-compose

```bash
BUILD_SHA=$(git rev-parse --short HEAD) docker compose up --build
```

### Verify

```bash
curl localhost:8080/ping     # → pong
curl localhost:8080/healthz  # → {"status":"ok"}
curl localhost:8080/version  # → {"sha":"..."}
```

## Container details

- Multi-stage build: `python:3.12-slim` builder → `python:3.12-slim` runtime
- Runs as non-root `appuser` (uid 1000) with `/usr/sbin/nologin`
- `HEALTHCHECK` uses Python stdlib (no curl/wget shipped in the image)
- Entrypoint: `gunicorn` with 2 workers

## Architecture (current)

```
                              ┌────────────────────────────────────────┐
                              │  minikube (single node, on EC2)        │
                              │                                        │
client ──HTTP──▶ Ingress (nginx) ──▶ Service (ClusterIP) ──▶ Pod(s) ──▶ gunicorn → flask app.py
                              │                            │           │
                              │                ConfigMap (BUILD_SHA) ──┤
                              │                Secret (DEMO_TOKEN)  ───┤
                              └────────────────────────────────────────┘
```

Day 2 adds the Helm-managed Kubernetes layer (see below). CI/CD (GitHub Actions) and observability (Prometheus + Grafana) land on Days 3–4.

## Kubernetes (Helm)

The service is packaged as a Helm chart at [`charts/app/`](./charts/app), with two environment overlays.

### Chart layout

```
charts/app/
├── Chart.yaml                  # name app, version 0.1.0, appVersion "0.1.0"
├── values.yaml                 # prod-shaped defaults with inline rationale
├── values-dev.yaml             # dev overlay (1 replica, dev host)
├── values-prod.yaml            # explicit prod overlay (2 replicas, prod host)
└── templates/
    ├── deployment.yaml         # probes on /healthz, envFrom ConfigMap+Secret, security context
    ├── service.yaml            # ClusterIP, port 80 → container 8080
    ├── ingress.yaml            # nginx class, host from values
    ├── configmap.yaml          # BUILD_SHA
    ├── secret.yaml             # DEMO_TOKEN placeholder, supplied at deploy time
    ├── serviceaccount.yaml
    ├── _helpers.tpl
    ├── NOTES.txt
    └── tests/test-connection.yaml
```

Scaffolded from `helm create`, then trimmed (removed bundled `hpa.yaml` and `httproute.yaml`) and customized.

### Environments

Two env overlays. The only intentional differences:

| Field | `values-dev.yaml` | `values-prod.yaml` |
|---|---|---|
| `replicaCount` | 1 | 2 |
| `ingress.hosts[0].host` | `devops-case.dev.local` | `devops-case.local` |

Everything else (resources, probes, security context, image, ConfigMap/Secret wiring) is intentionally identical so both environments exercise the same shape. Resources don't diverge because EC2 only has 4 GiB RAM — over-divergence at this scale would be theatrical. A real cluster would push prod limits higher.

Verify the rendered diff is exactly those two lines:

```bash
helm template app charts/app -f charts/app/values-dev.yaml  > /tmp/dev.yaml
helm template app charts/app -f charts/app/values-prod.yaml > /tmp/prod.yaml
diff /tmp/dev.yaml /tmp/prod.yaml
```

### Probes

Both probes hit `/healthz` (the existing app endpoint), with different timings:

| Probe | initialDelay | period | timeout | failureThreshold |
|---|---|---|---|---|
| **liveness** | 5 s | 10 s | 2 s | 3 |
| **readiness** | 2 s | 5 s | 2 s | 2 |

Liveness uses a longer interval so a transient hiccup doesn't restart the container; readiness is tighter so a stalled pod is pulled from the Service's endpoints quickly without killing it. Both target the named pod port `http` (8080).

### Resources

Per-container, applied to every replica in every env:

|  | requests | limits |
|---|---|---|
| **cpu** | 100m | 500m |
| **memory** | 128Mi | 256Mi |

Reasoning:

- **`requests: cpu 100m / mem 128Mi`** — sized for steady-state idle. Python + venv + 2 gunicorn workers sit at roughly that footprint at zero traffic.
- **`limits: cpu 500m`** — ~5× burst headroom so a brief request flood doesn't get CPU-throttled. CPU is compressible, so the limit isn't enforced as harshly as memory.
- **`limits: memory 256Mi`** — ~2× the request. Python worker memory tends to stay stable at the worker count, so the limit only needs slack to absorb one-shot allocations (e.g. logging a large payload). Going higher would waste cluster capacity on EC2's 4 GiB.

### Deploying

On a cluster where minikube + the nginx ingress addon are already running (see [`SETUP.md`](./SETUP.md)):

```bash
# Day 2 image strategy: build inside minikube's Docker daemon so the cluster
# can pull locally (no registry yet — GHCR push lands on Day 3).
eval $(minikube docker-env)
docker build --build-arg BUILD_SHA=$(git rev-parse --short HEAD) \
             -t devops-case-app:0.1.0 .

# Dev install
helm upgrade --install app charts/app -f charts/app/values-dev.yaml \
  --set config.BUILD_SHA=$(git rev-parse --short HEAD) \
  --set-string secret.DEMO_TOKEN=$(openssl rand -hex 16)

# Prod install (same release name; helm upgrades the running release)
helm upgrade --install app charts/app -f charts/app/values-prod.yaml \
  --set config.BUILD_SHA=$(git rev-parse --short HEAD) \
  --set-string secret.DEMO_TOKEN=$(openssl rand -hex 16)

kubectl rollout status deployment/app
kubectl get pods,svc,ingress
```

To reach the service through the ingress on minikube, add the host to `/etc/hosts`:

```bash
echo "$(minikube ip) devops-case.dev.local" | sudo tee -a /etc/hosts
curl http://devops-case.dev.local/ping        # → pong
```

### Rollout & rollback

Image-tag bumps and rollback go through standard Helm commands:

```bash
docker build --build-arg BUILD_SHA=$(git rev-parse --short HEAD) -t devops-case-app:0.1.1 .

helm upgrade app charts/app -f charts/app/values-prod.yaml \
  --reuse-values --set image.tag=0.1.1
kubectl rollout status deployment/app
helm history app                              # rev 1, 2, 3

helm rollback app                              # back to the previous revision
kubectl rollout status deployment/app
helm history app                              # rev 4 description: "Rollback to 2"
```

The `CHART` and `APP VERSION` columns in `helm history` track `Chart.yaml`'s `version`/`appVersion`, not the image tag. The image tag is what actually rolls — confirm with `kubectl get deployment app -o jsonpath='{.spec.template.spec.containers[0].image}'`.

Evidence for the Day 2 checkpoint (dev install, prod install, resources applied, rollout, rollback) lives in [`daily-checkpoints/day2-checkpoint.pdf`](./daily-checkpoints/day2-checkpoint.pdf).

## Project status

See [`PROGRESS.md`](./PROGRESS.md) for the live task list and day-by-day progress.

## Decisions (so far)

- **Why Python**: candidate familiarity. Tradeoff accepted: larger image than a Go binary.
- **Why Flask**: smallest dep footprint for three endpoints (vs FastAPI).
- **Why `python:3.12-slim`** base: balance between size and debuggability (vs distroless / alpine).
- **Why gunicorn (not `python app.py`)**: Flask's built-in server is single-threaded, has no crash recovery, and no graceful shutdown — it explicitly warns against use in production. gunicorn is a production WSGI server: it forks worker processes for real concurrency, the master process restarts crashed workers, and on `SIGTERM` it drains in-flight requests before exiting (matters for Kubernetes rolling updates on Day 2). Access logs go to stdout so `kubectl logs` works.

Full ADRs land on Day 4 under `docs/adr/`.

## AI assistant disclosure

AI assistance (Claude) was used throughout development. Tooling and reasoning behind key decisions are captured in the ADRs (Day 4) and in `PROGRESS.md`.
