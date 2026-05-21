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
host:8080  →  container (gunicorn → flask app.py)
```

Kubernetes (Helm), CI/CD (GitHub Actions), and observability (Prometheus + Grafana) land on Days 2–4.

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
