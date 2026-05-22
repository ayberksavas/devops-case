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

### Days 3–4
- ⬜ Day 3 — GitHub Actions (lint/test/build/Trivy/GHCR push), OIDC→AWS, gitleaks, v0.1.0 release, auto-deploy on merge
- ⬜ Day 4 — JSON logs, `/metrics`, kube-prometheus-stack, Grafana dashboard, alert rule, Terraform (Track A), RUNBOOK, SECURITY.md, ≥3 ADRs, architecture diagram

---

## Working directory

```
/Users/ayberksavas/Desktop/devops-case/
├── .github/
│   ├── CODEOWNERS                 # * → @ayberksavas
│   └── pull_request_template.md   # conventional commits checklist
├── charts/
│   └── app/                       # Helm chart for the service (Day 2)
│       ├── Chart.yaml             # name app, version 0.1.0, appVersion 0.1.0
│       ├── values.yaml            # prod-shaped defaults with inline rationale
│       ├── values-dev.yaml        # dev overlay (replicas=1, dev host)
│       ├── values-prod.yaml       # explicit prod overlay
│       └── templates/
│           ├── _helpers.tpl
│           ├── configmap.yaml     # BUILD_SHA
│           ├── deployment.yaml    # probes on /healthz, envFrom, security context
│           ├── ingress.yaml       # nginx class
│           ├── NOTES.txt
│           ├── secret.yaml        # DEMO_TOKEN placeholder
│           ├── service.yaml       # ClusterIP, 80 → 8080
│           ├── serviceaccount.yaml
│           └── tests/test-connection.yaml
├── daily-checkpoints/
│   ├── day0-checkpoint.pdf        # EC2 + SG + tool versions evidence (redacted)
│   ├── day1-checkpoint.pdf        # docker build/run/curl + non-root + git log + secret scan
│   └── day2-checkpoint.pdf        # dev install, prod install, resources, rollout, rollback
├── .dockerignore
├── .env.example                   # PORT, BUILD_SHA
├── .gitignore                     # python, secrets, macOS, IDE, .env (keeps .env.example)
├── Dockerfile                     # multi-stage, python:3.12-slim, non-root, HEALTHCHECK
├── PROGRESS.md                    # This file
├── README.md                      # setup, run, container, helm, decisions
├── SETUP.md                       # Day 0 infra log
├── app.py                         # Flask: /ping, /healthz, /version
├── docker-compose.yaml            # local-dev convenience
├── requirements.txt               # flask==3.0.3, gunicorn==23.0.0
├── requirements-dev.txt           # -r requirements.txt + pytest==8.3.3
├── test_app.py                    # 3 pytest tests covering all endpoints
└── .venv/                         # gitignored, local python env
```

EC2 access:
```bash
ssh -i devops-case.pem ubuntu@<elastic-ip>
```

The `.pem` lives outside this directory (don't commit). Elastic IP is in the AWS console.

### Git state (Day 2 — `feat/day2-helm-chart`, PR open)
- Active branch: `feat/day2-helm-chart`
- Commits on the branch (will squash-merge into `main` as one Day 2 commit):
  - **Commit 1** — `feat: add helm chart with dev/prod overlays` (chart files only)
  - **Commit 2** — `docs: document Day 2 chart usage` (this README/PROGRESS update)
  - **Commit 3** — `docs: add Day 2 checkpoint` (`daily-checkpoints/day2-checkpoint.pdf`)
- `main` history (unchanged since Day 1):
  - `329a4d7` — `test: add unit tests for /ping, /healthz, /version (#1)`
  - `ef40631` — `Initial commit`
- Branch protection still active on `main` (ruleset `protect-main`); PR review + squash-merge required.

---

## Open questions / unresolved

- Auto-deploy mechanism for Day 3.4: `kubectl set image` from CI vs ArgoCD GitOps. Decide at Day 3.
- Bonus picks at Day 2.5 (HPA / NetworkPolicy / PDB) and Day 3.5 (cosign / SBOM / multi-arch) — defer until core flow works.
- Image size optimisation (slim → distroless) — documented upgrade path; revisit if Trivy gets noisy on Day 3.

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
