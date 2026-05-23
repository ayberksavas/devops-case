# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
