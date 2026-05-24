# Daily checkpoints

Per-day evidence PDFs captured at the end of each working day, plus the
exported architecture diagram. Each PDF is a screenshot bundle backing
specific claims in [`../README.md`](../README.md) and
[`../PROGRESS.md`](../PROGRESS.md). The mapping to the case-study
submission checklist (`What to send us`, PDF page 10) is below.

## Submission-deliverable mapping

| Deliverable from the brief | Evidence file(s) here |
|---|---|
| Architecture diagram | `arch-diagram.png` (also rendered inline as Mermaid in `../README.md`) |
| Working demo — `/ping` returning `pong` | `day1-checkpoint.pdf` (API endpoints panel) |
| `kubectl get pods` / `helm list` / `helm history` / `kubectl rollout status` screenshots | `day2-checkpoint.pdf` (pages 1, 4, 5) |
| CI/CD workflow files with green-run evidence | `day3-checkpoint.pdf` (pipeline jobs, OIDC, gitleaks, Trivy, release, deploy) |
| Grafana dashboard screenshot (≥1 dashboard, ≥1 alert visible) | `day4-checkpoint.pdf` |

## What's in each file

### `arch-diagram.png`
PNG export of the runtime-topology Mermaid diagram from
`../README.md` (client → Elastic IP → nginx Ingress → Service → 2 pods,
with the observability overlay). Convenient attachment for the
submission email; the canonical version is the inline Mermaid block on
GitHub which re-renders automatically.

### `day0-checkpoint.pdf` *(3 pages)*
Day 0 — infrastructure setup evidence. Captured the moment the EC2 was
ready to host minikube.

- EC2 instance running with the Elastic IP attached
- Security group rules — SSH locked to `/32`, app ports + NodePort range open
- Tool versions on the EC2 host (Docker, kubectl, minikube, Helm)

Backs up `SETUP.md`. Not directly required by the submission checklist
but documents the starting AWS surface that Day 4.3 later codified in
OpenTofu.

### `day1-checkpoint.pdf` *(1 page)*
Day 1 — the container and the repo, all in one frame.

- `docker build` succeeds
- `docker run` works (container starts, ports bound)
- API endpoints respond (`/ping → pong`, `/healthz`, `/version`)
- Container runs as `appuser` (uid 1000), not root
- `HEALTHCHECK` reports healthy
- Clean `git log` (conventional-commit style)
- Secret scan over the working tree comes up empty

Covers the **"working demo: `/ping` → `pong`"** deliverable.

### `day2-checkpoint.pdf` *(5 pages)*
Day 2 — Helm installation, environments, rollout/rollback exercise.

| Page | Content |
|---|---|
| 1 | Dev install — `kubectl get pods,svc,ingress` for the dev overlay (1 replica, dev host), `helm list`, `kubectl describe pod` with the probes visible |
| 2 | Prod install — same shape with 2 replicas and the prod host |
| 3 | Container CPU/memory requests + limits applied (`kubectl describe` showing the values) |
| 4 | Rollout — image tag bump from `0.1.0` → `0.1.1`, `kubectl rollout status` succeeding |
| 5 | Rollback — `helm rollback app` reverts to revision 2, `helm history app` shows revision 4 with description `Rollback to 2`, `kubectl rollout status` confirms |

Covers the **kubectl / helm screenshots** deliverable.

### `day3-checkpoint.pdf` *(11 pages)*
Day 3 — CI/CD pipeline, supply chain, release, auto-deploy. The
longest checkpoint because Day 3 introduces multiple pieces; each
gets its own page or two.

- All CI pipeline jobs green (lint, test, gitleaks, AWS OIDC whoami,
  build/scan/push)
- Deploy job green on `main`, skipped on PRs (correctly gated by
  branch)
- Trivy image scan — 0 CRITICAL/HIGH vulnerabilities across all
  packages with `--ignore-unfixed`
- AWS OIDC federation working end-to-end (`aws sts get-caller-identity`
  output)
- Gitleaks secret scan with `--redact` and full git history
- Repository **Secrets** — empty (no static AWS credentials stored)
- Repository **Variables** — three present (`AWS_ROLE_ARN`,
  `AWS_REGION`, `EC2_INSTANCE_ID`); intentionally not secrets
- `v0.1.0` GitHub Release page
- GHCR `devops-case-app` versions (`:0.1.0`, `:latest`, `:main`, `:<short-sha>`)
- Auto-deploy on merge — workflow job log + SSM command invocation
- Post-deploy verification on the EC2 host (`/version` returning the
  merge SHA)

Covers the **CI/CD workflow files with green-run evidence** deliverable.

### `day4-checkpoint.pdf` *(3 pages)*
Day 4 — observability surface live on the cluster.

| Page | Content |
|---|---|
| 1 | Grafana "App overview" dashboard — RPS by path, latency p95 by path, 5xx error rate, pod restarts (15-minute delta). RPS panel shows a clear spike from a 200-request smoke loop; latency p95 is sub-millisecond. |
| 2 | Prometheus Alerts page — full rule-group view. `HighErrorRate` (under `app.rules`) sits in `inactive` (green) state; `Watchdog` is the only firing alert (by design — it's the kube-prometheus-stack's dead-man's-switch). |
| 3 | `HighErrorRate` rule expanded — full PromQL expression visible (`sum(rate(http_requests_total{status=~"5.."}[1m])) / sum(rate(http_requests_total[1m])) > 0.05 and sum(rate(http_requests_total[1m])) > 0`), `for: 5m`, severity `warning`. |

Covers the **Grafana dashboard + ≥1 alert rule** deliverable.

## Notes

- Screenshots contain real public IPs / resource IDs visible on-screen.
  The text accompanying the screenshots in the rest of the repo has
  been scrubbed of those values (see the Day 4.3 privacy sweep
  decisions in `../PROGRESS.md`).
- PDFs are immutable evidence — they're not regenerated retroactively
  if state on the cluster changes later. The Mermaid diagram in the
  main README *is* live and reflects the current architecture.
