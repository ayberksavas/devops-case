# Project Progress & Handoff

> **Purpose**: If a new session/agent starts here, read this file + `SETUP.md` to get fully oriented. The original brief is the PDF at `/Users/ayberksavas/Downloads/InsiderOne_DevOps_Internship_Case_Study_2026_v2.pdf`.

---

## What this project is

InsiderOne DevOps Internship Case Study (4-day edition, v2). Build a tiny HTTP service and ship it end-to-end like production: container → Kubernetes (Helm) → CI/CD → observability → public URL.

**Deliverables expected**: public repo, README, architecture diagram, Helm chart, GitHub Actions workflows, kubectl/helm screenshots, Grafana dashboard screenshot, public URL demo, RUNBOOK.md, SECURITY.md, ≥3 ADRs.

---

## Track: **A — Minikube on EC2**

Chosen for AWS exposure. See `SETUP.md` for the full infra log (EC2 type, security group, software install).

---

## Day plan (from the PDF)

| Day | Theme | Key tasks |
|-----|-------|-----------|
| 1 | Foundation | Tiny HTTP service, multi-stage Dockerfile (non-root), repo hygiene, 1–2 unit tests |
| 2 | Kubernetes & Helm | Helm chart (Deployment/Service/Ingress/ConfigMap/Secret), values-dev/prod, probes, rollout/rollback |
| 3 | CI/CD & Supply chain | GitHub Actions: lint/test/build/Trivy scan/GHCR push; OIDC to AWS; gitleaks; v0.1.0 release; auto-deploy on merge |
| 4 | Observability & Docs | JSON logs, /metrics, kube-prometheus-stack, ≥1 Grafana dashboard, ≥1 alert, Terraform/OpenTofu for EC2+EIP+SG, RUNBOOK, ADRs, architecture diagram |

---

## Decisions made so far

1. **Track A** (Minikube on EC2) over Track B (local + tunnel) — for AWS hands-on exposure. *(see SETUP.md)*
2. **EC2 instance**: `c7i-flex.large` (2 vCPU, 4 GiB RAM), Ubuntu 26.04, 20 GiB gp3, free-tier eligible. *(see SETUP.md)*
3. **Security group**: SSH restricted to my IP /32; 80/443 + NodePort range (30000–32767) open. *(see SETUP.md)*
4. **Minikube driver**: Docker, with `--cpus=2 --memory=3500mb` to leave headroom on the 4 GiB instance.
5. **Language for HTTP service**: **Python** — chosen because the candidate knows it best. Tradeoff accepted: image will be larger than a Go binary and Trivy may surface more runtime CVEs to manage at Day 3.
6. **Framework**: **Flask** — smallest dep footprint, simplest for 3 endpoints, smaller resulting image vs FastAPI.
7. **Runtime base image**: `python:3.12-slim` with explicit non-root `appuser` (uid 1000). Chosen over distroless and alpine: distroless ships best Trivy results but no shell makes debugging harder; alpine's musl libc is a footgun if we add C-extension deps later. Slim is the balance pick — distroless remains the documented upgrade path.
8. **Web server**: gunicorn with 2 workers (entrypoint of the container). Flask dev server is not used in the image.
9. **Repo name**: `devops-case` on GitHub under `ayberksavas` (public). Repo URL: `https://github.com/ayberksavas/devops-case`. Default branch `main`. Working with main + feature branches, conventional commits, squash-merge PRs.
10. **Branch protection on `main`**: ruleset `protect-main` applied — require PR before merging, **0 required approvals** (solo project, GitHub blocks self-approval), require linear history, require status checks (no checks configured yet — to wire on Day 3). Force pushes and deletions off. Admin bypass left ON as an escape hatch.
11. **Helm chart layout**: `charts/app/` (chart name `app`), scaffolded from `helm create` then trimmed (removed bundled `hpa.yaml`, `httproute.yaml`) and customized. Env overlays live at the chart root as `values-dev.yaml` / `values-prod.yaml`. Matches the PDF's example command shape and leaves room for a second chart later (e.g. observability stack on Day 4).
12. **Image strategy for Day 2**: build inside minikube's Docker daemon on EC2 via `eval $(minikube docker-env)` with `imagePullPolicy: IfNotPresent`. No registry yet — GHCR push lands on Day 3 with the same tag scheme, so this stops being needed.
13. **Dev/prod diff locked at two values**: `replicaCount` and `ingress.hosts[0].host`. Resources stay aligned because EC2 has only 4 GiB RAM and over-divergence at this scale would be theatrical. PDF checkpoint specifically asks for "different replica and host values" — anything more is polish.
14. **Secret approach**: chart includes a Secret manifest with placeholder `DEMO_TOKEN` supplied at deploy time via `--set-string`. Not consumed by the app yet — demonstrates the wiring (Secret → `envFrom`) without inventing a fake feature, while ticking the PDF's task 2.1 list.
15. **Bonus 2.5 skipped**: HPA / NetworkPolicy / PDB deferred. Core Day 2 flow worked cleanly without them; revisiting would have required additional templates and cluster verification for no functional gain on a single-node minikube.
16. **Linter: ruff** over flake8 + black. Single binary, ~100× faster, sensible zero-config defaults. Config in `pyproject.toml` with rule set `E` (pycodestyle), `F` (pyflakes), `I` (isort), `B` (flake8-bugbear), `UP` (pyupgrade). `ruff format --check` not run yet — adds noise without value at this code size.
17. **Direct binary install for gitleaks and trivy** instead of their wrapper actions. Two different causes converged on the same fix:
    - `gitleaks/gitleaks-action@v2` requires a paid `GITLEAKS_LICENSE` env var for org accounts (personal accounts are free today, but the licensing model has wobbled).
    - `aquasecurity/trivy-action` and `aquasecurity/setup-trivy` both do an internal sparse-checkout of `aquasecurity/trivy` with `--filter=blob:none`. The resulting promisor remote flakes intermittently on hosted runners with `could not read Username for 'https://github.com': terminal prompts disabled`. Confirmed by a green re-run of the same workflow with no code change.
    Trade-off: versions are pinned in the workflow file (`GITLEAKS_VERSION=8.30.1`, `TRIVY_VERSION=0.70.0`) and must be bumped manually. Accepted because the pattern is consistent, ~5 lines, and avoids the flake entirely.
18. **AWS region: `eu-north-1`** (Stockholm) — matches the EC2 region from Day 0. No multi-region setup planned.
19. **OIDC role scope**: trust policy `sub` claim is `repo:ayberksavas/devops-case:*` (any branch/ref in this repo). Could tighten to `:ref:refs/heads/main` once 3.4 deploy lands, but the wildcard makes it easier to demo from PR runs too. No permission policies attached yet — `sts:GetCallerIdentity` works without any. Day 3.4 will add `ssm:SendCommand` scoped to the EC2 instance.
20. **OIDC config via repo variables, not secrets**: `AWS_ROLE_ARN` and `AWS_REGION` are identifiers, not credentials. The entire point of OIDC is that no credential material lives in repo storage. Variables fit the semantics; secrets would falsely imply something to protect.
21. **CHANGELOG format**: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) — `[Unreleased]` placeholder + dated `[X.Y.Z]` sections. Chosen for tooling compatibility (release-please etc. can parse it) and because it's the obvious standard.
22. **`:latest` tracks releases, not `main`**: metadata-action enables `:latest` only on `github.ref_type == 'tag'`. Registry convention is that `:latest` means "latest released version", not "latest commit". Main commits get pinned via `:main` and `:<short-sha>` instead.
23. **Auto-deploy via CI push (OIDC + SSM), not GitOps**: chose `kubectl set image` flavor — specifically `aws ssm send-command` invoking `bash scripts/deploy.sh <sha>` on the EC2 instance — over ArgoCD/Flux. Rationale: extends the existing OIDC role with one inline IAM policy and adds one workflow job; ArgoCD would add a ~500 MiB control plane on the 4 GiB EC2 plus an `Application` CR for marginal benefit on a single-node single-app cluster. GitOps is the right answer at multi-app multi-team scale; here it would be ceremony.
24. **EC2 holds a checkout of the repo at `/opt/devops-case`** (owned by `ubuntu`) rather than having CI render manifests and ship them via SSM. Reason: rendered Helm output is larger than the 4 KiB SSM inline-command limit, and the alternatives (S3 hop, base64-compressed YAML, etc.) add moving parts. A `git fetch && reset --hard origin/main` on the instance is one network round-trip and keeps the deploy script tiny. Trade-off: the cluster host needs git connectivity to GitHub (already does for `git pull` to work), and the repo is duplicated between CI runner and EC2.
25. **Prometheus metrics use `prometheus_client` multiprocess mode**, not a single-worker workaround. gunicorn runs 2 workers (decision #8, kept for production realism), so without coordination each worker would hold its own counters and Prometheus scrapes would see flickering totals — fatal for Day 4.2's RPS/error-rate dashboards. The standard fix: set `PROMETHEUS_MULTIPROC_DIR` on the container, add a `child_exit` hook in `gunicorn.conf.py` that calls `multiprocess.mark_process_dead(worker.pid)`, and have `/metrics` instantiate a fresh `CollectorRegistry` + `MultiProcessCollector` per scrape. In Kubernetes the chart mounts an `emptyDir` (`medium: Memory`, 16Mi) at that path; rollout = clean counter slate, which is the desired behaviour. Alternatives rejected: (a) drop to 1 worker — reverses decision #8 and removes any concurrency story; (b) live with per-worker drift and document it — makes the 4.2 dashboards lie.
26. **Gunicorn config moved to `gunicorn.conf.py`** instead of inline CLI flags in the Dockerfile ENTRYPOINT. Driven by decision #25 (needs the `child_exit` hook), but also lets us disable gunicorn's plaintext access log in one place — the Flask `after_request` hook is the single source of per-request log lines, all in JSON.
27. **Two app metrics, both labelled by matched URL rule (not raw path)**: `http_requests_total{method,path,status}` (Counter) and `http_request_duration_seconds{method,path}` (Histogram). Labelling on `request.url_rule.rule` instead of `request.path` keeps cardinality bounded — an unknown URL with arbitrary query/path noise can't blow up the time series store. Unmatched routes fall into a single `unmatched` bucket. `/metrics` itself is excluded so the scrape doesn't bias its own series.
28. **kube-prometheus-stack runs on a slim values profile**, not the defaults. The 4 GiB EC2 hosts minikube + the app + Linux; a default install reserves ~2 GiB for Prometheus alone and would OOM the host. `monitoring/values.yaml` trims Prometheus to 250Mi/600Mi req/limit with 2-day retention and `emptyDir` storage; sets `serviceMonitorSelectorNilUsesHelmValues: false` (and same for PodMonitor / Rule / Probe) so the operator picks up SMs regardless of release-label; disables scraping for `kube-controller-manager` / `kube-scheduler` / `kube-proxy` / etcd (minikube doesn't expose them); tightens Alertmanager / Grafana / node-exporter resources. Trade-off: a Prometheus pod restart wipes history because there's no PVC, which is acceptable on a demo cluster but not in real prod. Total footprint lands around 700–900 MiB, leaving plenty of headroom for the app and Linux.
29. **Stack install is a bash script (`scripts/install-monitoring.sh`), not a sub-chart**. The script mirrors `scripts/deploy.sh` from Day 3.4 — one idempotent `helm upgrade --install`, version-pinned (chart `65.5.0`), with the values file referenced as `-f monitoring/values.yaml`. A `charts/observability/` sub-chart with kube-prometheus-stack as a dependency would add a `Chart.lock` for version pinning but introduce a wrapper-chart with one external dependency, and the "why a wrapper for one external dep?" question doesn't have a good answer at this scale. The script is the simpler, more easily explained shape.
30. **Monitoring resources (`ServiceMonitor`, `PrometheusRule`, dashboard `ConfigMap`) live as templates in the app chart**, gated by a `monitoring.enabled` feature flag. Reason: they describe the *app's* observability surface, so they belong with the chart that ships the app. A single Helm release upgrades both code and monitoring together. The flag default (`false`) keeps the chart installable on a cluster without the kube-prometheus-stack CRDs (otherwise `helm install` errors with `no matches for kind "ServiceMonitor"`); `values-prod.yaml` flips it on. Install ordering on a fresh cluster: stack first (`scripts/install-monitoring.sh`), then app with the prod overlay.
31. **Grafana dashboards are provisioned via a labelled `ConfigMap`** (the `grafana_dashboard: "1"` label, with the stack's Grafana sidecar set to `searchNamespace: ALL`), not via Grafana's HTTP API or a datasource provider config. Reason: "drop a labelled ConfigMap, get a dashboard" is the simplest possible provisioning path — no API tokens, no UID stability problems, no Grafana login required, and the dashboard JSON lives in version control next to the chart it documents. The dashboard JSON itself sits at `charts/app/dashboards/app-overview.json` and is read into the ConfigMap via `.Files.Get`, so the template stays small.
32. **`HighErrorRate` alert has an explicit div-by-zero guard**. The natural expression is `5xx_rate / total_rate > 0.05`, but on an idle service `total_rate` is 0, and `0/0` in PromQL is `NaN` — the comparison silently fails and the alert never fires. Adding `and sum(rate(http_requests_total[1m])) > 0` makes the intent explicit: only alert when there is enough traffic for a ratio to be meaningful. The cost is two extra lines; the benefit is anyone reading the rule sees the design choice instead of wondering whether the alert is "broken" when it just hasn't seen requests.

---

## Current state

### Infra (Day 0)
- ✅ EC2 + EIP + security group provisioned (4 inbound rules: SSH /32, 80, 443, NodePort 30000–32767)
- ✅ Docker, kubectl (v1.36.1), minikube (running, 1 node Ready), Helm installed on EC2
- ✅ Evidence captured in `daily-checkpoints/day0-checkpoint.pdf` (EC2 dashboard, SG rules with account ID + home IP redacted, tool versions, cluster status)

### Day 1 — Foundation ✅ COMPLETE
- ✅ **1.1** Flask service (`app.py`, `requirements.txt`, `.env.example`) — three endpoints, env-driven config, verified locally with curl
- ✅ **1.2** Multi-stage Dockerfile + `.dockerignore` + `docker-compose.yaml` — built (229 MB), ran as `appuser` (uid 1000), `HEALTHCHECK` reports `healthy`, `BUILD_SHA` injection verified via `/version`
- ✅ **1.3** Repo hygiene — `.gitignore`, `README.md`, `.github/pull_request_template.md`, `.github/CODEOWNERS` in repo; public GitHub repo created and pushed; branch protection (`protect-main` ruleset) active on `main`; first feature-branch → PR → squash-merge cycle exercised
- ✅ **1.4** Unit tests — `test_app.py` (3 pytest tests covering `/ping`, `/healthz`, `/version`) + `requirements-dev.txt`. Merged via PR #1 (`test/add-unit-tests` → `main`). Local-only for now; will be wired into CI on Day 3.
- ✅ **Day 1 checkpoint** — `docker build` / `docker run` / `curl /ping → pong`, clean git log (2 commits), no secrets in repo, non-root user proven, HEALTHCHECK healthy. Evidence in `daily-checkpoints/day1-checkpoint.pdf`.

### Day 2 — Kubernetes & Helm ✅ COMPLETE
- ✅ **2.1** Helm chart at `charts/app/` with Deployment / Service / Ingress / ConfigMap / Secret. Scaffolded from `helm create`, trimmed and customized: probes on `/healthz`, pod + container security context (non-root uid 1000, drop ALL caps), `envFrom` wires ConfigMap (`BUILD_SHA`) + Secret (`DEMO_TOKEN`), checksum annotations roll pods on config change.
- ✅ **2.2** Two env overlays: `values-dev.yaml` (1 replica, host `devops-case.dev.local`) and `values-prod.yaml` (2 replicas, host `devops-case.local`). `helm template` diff between them is exactly those two lines. Both deployed and verified on minikube — see checkpoint PDF.
- ✅ **2.3** Liveness + readiness probes against `/healthz` with distinct timings (liveness 5s/10s, readiness 2s/5s); requests `cpu 100m / mem 128Mi`, limits `cpu 500m / mem 256Mi`. Rationale documented in README.
- ✅ **2.4** Rollout/rollback exercised: built `devops-case-app:0.1.1`, `helm upgrade --set image.tag=0.1.1` rolled to revision 3, `helm rollback app` reverted to revision 2 (`helm history` shows rev 4 description `Rollback to 2`). `kubectl rollout status` reported success for both transitions.
- ⏭ **2.5** Bonus (HPA / NetworkPolicy / PDB) intentionally skipped — see decision #15.
- ✅ **Day 2 checkpoint** — five-page PDF at `daily-checkpoints/day2-checkpoint.pdf` covers dev install (1 pod, dev host, probes healthy), prod install (2 pods, prod host, deployment 2/2), container CPU/memory requests & limits applied on running pods, rollout to 0.1.1, rollback to 2.

### Day 3 — CI/CD & Supply chain ✅ COMPLETE
- ✅ **3.1** GitHub Actions pipeline at `.github/workflows/ci.yml` — jobs `lint (ruff)`, `test (pytest)`, `build, scan, push`. Triggers on PR, push to `main`, push to `v*` tags, and `workflow_dispatch`. `docker/metadata-action` produces `:<short-sha>` + `:main` on main push, `:<semver>` + `:latest` on tag push, `:pr-N` on PRs (built+scanned only, never pushed). Trivy gates push on CRITICAL/HIGH with `--ignore-unfixed`. Merged via PR #5.
- ✅ **3.2** Secrets & auth — two PRs, both merged:
  - **Gitleaks** (PR #6) — full-history scan (`fetch-depth: 0`) with `--redact` so any finding doesn't re-leak through the public Action log. Binary install (see decision #17).
  - **AWS OIDC** (PR #7) — IAM OIDC identity provider for `token.actions.githubusercontent.com` created in account `809338888160` (eu-north-1). Role `github-actions-devops-case` with trust policy scoped to `repo:ayberksavas/devops-case:*` and no permission policies attached. Workflow's `aws OIDC (whoami)` job assumes the role and runs `aws sts get-caller-identity` on every event as a federation proof. Role ARN + region stored as repo *variables* (decision #20).
- ✅ **3.3** Release hygiene — `CHANGELOG.md` (Keep a Changelog) merged via PR #8. Trivy install switched from `aquasecurity/setup-trivy@v0.2.6` to direct binary download (decision #17) — merged via the trivy-fix + docs PR. Tag `v0.1.0` pushed from `main`; CI auto-published `:0.1.0` + `:latest` to GHCR; GitHub Release page exists at `releases/tag/v0.1.0` with notes extracted from CHANGELOG. Chart `appVersion`, git tag, and image tag all aligned.
- ✅ **3.4** Auto-deploy on merge — chose CI-push via OIDC + SSM (decision #23). Extended OIDC role with inline `DeployViaSSM` policy (decision #24). EC2 got an `AmazonSSMManagedInstanceCore` instance profile and an `ubuntu`-owned `/opt/devops-case` checkout. New `deploy (ssm → ec2 → helm)` job in `ci.yml` invokes `scripts/deploy.sh` on the instance via `aws ssm send-command` after every successful main-branch build. Stdout/stderr captured and printed in the workflow log.
- ⏭ **3.5** Bonus (cosign / SBOM / multi-arch / release-please) — intentionally skipped. Day 4 has its own scope (observability + IaC + docs) and consumed bonus would push core work to overflow.

### Day 4 — Observability & Docs
- ✅ **4.1** Logs & metrics
  - **Structured JSON logs** — stdlib `logging` with a custom `JsonFormatter`. One JSON object per stdout line. Required fields (`timestamp`, `level`, `msg`, `request_id`) plus per-request extras (`method`, `path`, `status`, `duration_ms`).
  - **Request ID middleware** — `before_request` reads `X-Request-ID` from the client (echo) or generates a fresh UUID4 hex; `after_request` writes it back on the response header and includes it in the log line. Stored on `flask.g` for the request scope.
  - **`/metrics` endpoint** — Prometheus exposition format. Two app-level series (Counter, Histogram) labelled by matched URL rule (decision #27), `/metrics` excluded from itself.
  - **gunicorn config file** at repo root — disables gunicorn's plain access log (we emit JSON from Flask) and runs the multiprocess cleanup hook. Decision #26.
  - **Multiprocess metrics** via `prometheus_client.multiprocess` — `PROMETHEUS_MULTIPROC_DIR` env in the image, `mark_process_dead(worker.pid)` on `child_exit`, `MultiProcessCollector` per scrape. Helm chart mounts an `emptyDir` (`medium: Memory`, 16Mi) at the multiproc dir so rollouts reset cleanly. Decision #25.
  - **Tests** — 7/7 pytest pass (up from 3): added coverage for `/metrics` response shape, `X-Request-ID` generation and round-trip, and `JsonFormatter` field shape.
  - **Verified locally** — ruff clean, pytest green, Flask-dev smoke OK, gunicorn 2-worker smoke confirmed multiproc aggregation produces summed counters (`http_requests_total{path="/ping"} 10.0` after 10 requests against 2 workers, with both `counter_<pid>.db` files present in the multiproc dir).
- ✅ **4.2** Prometheus + Grafana
  - **kube-prometheus-stack** installed at chart version `65.5.0` in the `monitoring` namespace (release name `kps`). One bash script wraps the helm install for repeatability — `scripts/install-monitoring.sh`. Decision #29.
  - **Slim profile** at `monitoring/values.yaml` — trims Prometheus to 250Mi/600Mi req/limit, 2-day retention, `emptyDir` TSDB; disables scraping of `kube-controller-manager` / `kube-scheduler` / `kube-proxy` / etcd (minikube doesn't expose them); tightens Alertmanager / Grafana / node-exporter resources. Total stack footprint ≈700–900 MiB on the 4 GiB EC2. Each override annotated in-file. Decision #28.
  - **Scrape wiring** — `charts/app/templates/servicemonitor.yaml` points Prometheus at the app's `/metrics` (port `http`, 15s). Picked up by the operator because the slim values set `serviceMonitorSelectorNilUsesHelmValues: false`.
  - **Alert** — `charts/app/templates/prometheusrule.yaml`: `HighErrorRate` fires when 5xx ratio > 5% over 1m for 5m sustained. Explicit `and sum(rate(http_requests_total[1m])) > 0` guard prevents NaN-on-idle silently never firing. Decision #32.
  - **Dashboard** — `charts/app/dashboards/app-overview.json` shipped via `charts/app/templates/dashboard-configmap.yaml` (labelled `grafana_dashboard: "1"`, picked up by Grafana's sidecar at `searchNamespace: ALL`). Four panels: RPS by path, p95 latency by path, 5xx rate, pod restarts (15m delta). Decision #31.
  - **`monitoring.enabled` flag** in `values.yaml` (default `false`) and `values-prod.yaml` (flipped to `true`) gates all three monitoring resources so the chart still installs on a cluster without the kube-prometheus-stack CRDs. Decision #30.
  - **Verified on EC2** — stack pods all `Running`; both app pods `up` as scrape targets (`serviceMonitor/default/app/0`); `HighErrorRate` loaded and `inactive`; `Watchdog` firing as expected (dead-man's switch for the pipeline); dashboard renders RPS spike from a 200-request smoke loop with sub-millisecond p95.
- ⬜ **4.3** IaC — Terraform/OpenTofu for EC2 + EIP + SG (scope of OIDC role/instance profile still open — see "Open questions")
- ⬜ **4.4** Architecture & docs — RUNBOOK.md, SECURITY.md, ≥3 ADRs, architecture diagram

---

## Working directory

```
/Users/ayberksavas/Desktop/devops-case/
├── .github/
│   ├── CODEOWNERS                 # * → @ayberksavas
│   ├── pull_request_template.md   # conventional commits checklist
│   └── workflows/
│       └── ci.yml                 # lint, test, gitleaks, AWS OIDC, build/scan/push (Day 3)
├── charts/
│   └── app/                       # Helm chart for the service (Day 2)
│       ├── Chart.yaml             # name app, version 0.1.0, appVersion 0.1.0
│       ├── values.yaml            # prod-shaped defaults with inline rationale
│       ├── values-dev.yaml        # dev overlay (replicas=1, dev host)
│       ├── values-prod.yaml       # explicit prod overlay
│       ├── dashboards/
│       │   └── app-overview.json # 4-panel Grafana dashboard JSON (Day 4.2)
│       └── templates/
│           ├── _helpers.tpl
│           ├── configmap.yaml     # BUILD_SHA
│           ├── dashboard-configmap.yaml  # ConfigMap wrapping the dashboard JSON, labelled for Grafana sidecar pickup (Day 4.2)
│           ├── deployment.yaml    # probes on /healthz, envFrom, security context
│           ├── ingress.yaml       # nginx class
│           ├── NOTES.txt
│           ├── prometheusrule.yaml # HighErrorRate alert, gated by monitoring.enabled (Day 4.2)
│           ├── secret.yaml        # DEMO_TOKEN placeholder
│           ├── service.yaml       # ClusterIP, 80 → 8080
│           ├── serviceaccount.yaml
│           ├── servicemonitor.yaml # scrape /metrics, gated by monitoring.enabled (Day 4.2)
│           └── tests/test-connection.yaml
├── daily-checkpoints/
│   ├── day0-checkpoint.pdf        # EC2 + SG + tool versions evidence (redacted)
│   ├── day1-checkpoint.pdf        # docker build/run/curl + non-root + git log + secret scan
│   └── day2-checkpoint.pdf        # dev install, prod install, resources, rollout, rollback
├── .dockerignore
├── .env.example                   # PORT, BUILD_SHA
├── .gitignore                     # python, secrets, macOS, IDE, .env (keeps .env.example)
├── CHANGELOG.md                   # Keep a Changelog format; tracks v0.1.0+ (Day 3)
├── Dockerfile                     # multi-stage, python:3.12-slim, non-root, HEALTHCHECK
├── gunicorn.conf.py               # bind/workers + multiprocess cleanup + JSON-only logging (Day 4.1)
├── PROGRESS.md                    # This file
├── README.md                      # setup, run, container, helm, CI/CD, decisions
├── SETUP.md                       # Day 0 infra log
├── app.py                         # Flask: /ping, /healthz, /version
├── docker-compose.yaml            # local-dev convenience
├── monitoring/
│   └── values.yaml                # slim profile for kube-prometheus-stack (Day 4.2)
├── pyproject.toml                 # ruff config (Day 3)
├── requirements.txt               # flask==3.0.3, gunicorn==23.0.0, prometheus-client==0.21.0
├── requirements-dev.txt           # -r requirements.txt + pytest==8.3.3, ruff==0.7.4
├── scripts/
│   ├── deploy.sh                  # runs on EC2 via SSM after main merge (Day 3.4)
│   └── install-monitoring.sh      # idempotent install of kube-prometheus-stack (Day 4.2)
├── test_app.py                    # 7 pytest tests (endpoints, /metrics, request_id, JSON formatter)
└── .venv/                         # gitignored, local python env
```

EC2 access:
```bash
ssh -i devops-case.pem ubuntu@<elastic-ip>
```

The `.pem` lives outside this directory (don't commit). Elastic IP is in the AWS console.

### Git state (end of Day 3)
- `main` history through Day 3 (PR numbers):
  - `#5` — `ci: add GitHub Actions pipeline (lint, test, Trivy scan, GHCR push)` (3.1)
  - `#6` — `ci: add gitleaks secret scan job` (3.2 secrets)
  - `#7` — `ci: add AWS OIDC whoami job (no long-lived keys)` (3.2 OIDC)
  - `#8` — `docs: add CHANGELOG for v0.1.0` (3.3, release notes)
  - `#9` — `chore: fix flaky trivy install + document Day 3 in README and PROGRESS` (trivy binary install + first batch of Day 3 docs)
  - `#10` (this PR) — `feat: auto-deploy to minikube via OIDC + SSM after merge` (3.4)
- Tags: `v0.1.0` cut after #9 merged; CI auto-published `ghcr.io/ayberksavas/devops-case-app:0.1.0` and `:latest`. GitHub Release page at `releases/tag/v0.1.0`.
- Branch protection on `main` (`protect-main` ruleset) — required status checks: `lint (ruff)`, `test (pytest)`, `gitleaks (secret scan)`, `build, scan, push` (wired after first green run on `main`).

---

## Open questions / unresolved

- **Image size optimisation (slim → distroless)** — documented upgrade path. Not needed in practice: Trivy is clean at CRITICAL/HIGH with `--ignore-unfixed`, so `python:3.12-slim` is fine for now.
- **OIDC trust scope tightening** — currently any ref in the repo can assume the role (`repo:ayberksavas/devops-case:*`). Now that 3.4 deploy is wired, could tighten to `:ref:refs/heads/main` for the deploy role. Keeping the wildcard for now so PR runs can still demo `aws sts get-caller-identity`.
- **Day 4 Terraform scope** — at minimum the EC2 + EIP + SG (PDF asks for this). Could also pull in the OIDC provider, OIDC role, EC2 instance profile, and the inline `DeployViaSSM` policy from Day 3 to fully codify the AWS surface. Decide at Day 4.

---

## How to verify the current build (Day 1 checkpoint)

```bash
# 1. Run tests
pip install -r requirements-dev.txt
pytest -v                                       # 3 passed

# 2. Container build + run
docker build -t devops-case-app:day1 .
docker run --rm -d --name d1-check -p 8080:8080 -e BUILD_SHA=day1 devops-case-app:day1

# 3. Hit all three endpoints
curl localhost:8080/ping       # pong
curl localhost:8080/healthz    # {"status":"ok"}
curl localhost:8080/version    # {"sha":"day1"}

# 4. Verify non-root user and HEALTHCHECK
docker exec d1-check id                                            # uid=1000(appuser)
docker inspect --format='{{.State.Health.Status}}' d1-check        # healthy

# 5. Repo hygiene
git log --oneline                                                  # clean, conventional commits
git grep -iE "secret|password|api_key" -- ':!.gitignore' ':!*.md'  # no matches

# 6. Cleanup
docker rm -f d1-check
```

---

## AI assistant note

Per the case study house rule: AI assistant usage is fine, just disclose. Whatever ends up in the final README needs a short note on which AI was used and the reasoning behind key decisions.
