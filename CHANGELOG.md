# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Structured JSON logs** — stdlib `logging` with a custom `JsonFormatter` emits
  one JSON object per log line on stdout. Per-request access log carries
  `timestamp`, `level`, `msg`, `request_id`, `method`, `path`, `status`, and
  `duration_ms`. Log level configurable via `LOG_LEVEL` (default `INFO`).
- **Request ID propagation** — every request gets an `X-Request-ID` (echoed
  back from the client header if present, otherwise a fresh UUID4 hex). The
  same value appears on the response header and in the access log line.
- **`/metrics` endpoint** — Prometheus exposition format with two app-level
  series: `http_requests_total{method,path,status}` (Counter) and
  `http_request_duration_seconds{method,path}` (Histogram). The scrape endpoint
  itself is excluded from these series.
- **Gunicorn config file** (`gunicorn.conf.py`) — runs `prometheus_client`'s
  `multiprocess.mark_process_dead` from the `child_exit` hook so per-worker
  metric files don't leak counters from gone PIDs across rollouts. Also
  disables gunicorn's plaintext access log (the Flask after-request hook emits
  the structured JSON one).
- **Helm chart** — `emptyDir` (`medium: Memory`, 16Mi) mounted at
  `/tmp/prometheus_multiproc` so the multiprocess metric files survive across
  worker restarts within the pod and reset cleanly on rollout.

### Changed

- **Dockerfile entrypoint** — now `gunicorn -c gunicorn.conf.py app:app`
  (replaces the inline `--bind / --workers / --access-logfile` flags). New
  env var `PROMETHEUS_MULTIPROC_DIR=/tmp/prometheus_multiproc` and the
  directory is pre-created and chowned to `appuser` in the runtime image.

### Added (Day 4.2 — Prometheus + Grafana)

- **kube-prometheus-stack** installed on the cluster via a slim values
  profile at `monitoring/values.yaml` and an idempotent install script at
  `scripts/install-monitoring.sh` (pinned to chart version `65.5.0`).
  Slim profile fits the 4 GiB EC2: Prometheus 250Mi/600Mi request/limit,
  2-day retention, `emptyDir` TSDB instead of a PVC, disabled scraping of
  `kube-controller-manager` / `kube-scheduler` / `kube-proxy` / etcd
  (minikube doesn't expose them). Total stack footprint ≈700–900 MiB.
- **Scrape target wiring** — `charts/app/templates/servicemonitor.yaml`
  declares a `ServiceMonitor` that points Prometheus at the app's `/metrics`
  endpoint (15s interval, port `http`). Picked up by the operator without
  any release-label gymnastics because the slim values set
  `serviceMonitorSelectorNilUsesHelmValues: false`.
- **Alert rule** — `charts/app/templates/prometheusrule.yaml` defines
  `HighErrorRate`: 5xx ratio over a 1-minute window > 5% for 5 minutes,
  with an explicit `and sum(rate(http_requests_total[1m])) > 0` guard
  against div-by-zero on an idle service.
- **Grafana dashboard** — JSON at `charts/app/dashboards/app-overview.json`,
  shipped via `charts/app/templates/dashboard-configmap.yaml` as a
  `ConfigMap` carrying the `grafana_dashboard: "1"` label. Grafana's
  sidecar (set to `searchNamespace: ALL` in the slim values) discovers
  it automatically across namespaces. Four panels: RPS by path, p95
  latency by path, 5xx error rate, pod restarts (15-minute delta).
- **`monitoring.enabled` flag** in the app chart — gates the three
  monitoring resources above. Default `false` so the chart still
  installs cleanly on a cluster without the kube-prometheus-stack CRDs.
  `values-prod.yaml` flips it to `true`.

## [0.1.0] - 2026-05-23

First tagged release. Covers Days 0–3 of the InsiderOne DevOps case study:
the service, its container, the Helm chart, and the CI pipeline that lints,
tests, scans, and publishes it.

### Added

- **Service** — Flask app exposing `GET /ping`, `GET /healthz`, and `GET /version`.
  Configuration via `PORT` and `BUILD_SHA` env vars.
- **Container** — Multi-stage Dockerfile on `python:3.12-slim`, runs as non-root
  `appuser` (uid 1000) with `/usr/sbin/nologin`. Entrypoint is `gunicorn` (2 workers);
  `HEALTHCHECK` uses Python stdlib (no curl/wget shipped in the runtime layer).
- **Helm chart** — `charts/app/` with Deployment, Service, Ingress, ConfigMap, Secret.
  Liveness and readiness probes target `/healthz`. Container resources: requests
  `cpu 100m / mem 128Mi`, limits `cpu 500m / mem 256Mi`. Pod-level securityContext
  enforces `runAsNonRoot` and drops all capabilities.
- **Environments** — `values-dev.yaml` (1 replica, dev host) and `values-prod.yaml`
  (2 replicas, prod host). All other values intentionally identical so both envs
  exercise the same shape.
- **CI pipeline** (`.github/workflows/ci.yml`) running on every PR, push to `main`,
  and `v*` tag:
  - `lint` — ruff with E/F/I/B/UP rule set
  - `test` — pytest (3 unit tests covering all endpoints)
  - `gitleaks` — full-history secret scan with `--redact`
  - `aws OIDC (whoami)` — assumes an IAM role via GitHub's OIDC token and
    runs `aws sts get-caller-identity` (no long-lived AWS credentials in repo or CI)
  - `build, scan, push` — Docker build, Trivy scan failing on CRITICAL/HIGH
    (`--ignore-unfixed`), conditional push to GHCR. PRs build and scan only;
    `main` pushes `:main` and `:<short-sha>`; `v*` tags push `:<semver>` and `:latest`.
- **Repo hygiene** — `.gitignore`, `.env.example`, `.dockerignore`, `docker-compose.yaml`
  for local dev, `pyproject.toml` (ruff config), CODEOWNERS, PR template, branch
  protection on `main` requiring all CI checks green.

### Image artifacts

This release publishes:

- `ghcr.io/ayberksavas/devops-case-app:0.1.0`
- `ghcr.io/ayberksavas/devops-case-app:latest`

The chart's `appVersion` is `0.1.0`, matching the image tag.

[Unreleased]: https://github.com/ayberksavas/devops-case/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ayberksavas/devops-case/releases/tag/v0.1.0
