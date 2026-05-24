# ADR 0003 — Observability via kube-prometheus-stack (slim profile)

**Status:** Accepted (2026-05-24, Day 4.2)

**Supersedes:** none

**Superseded by:** none

## Context

Day 4 asks for `/metrics` on the app (4.1), at least one Grafana
dashboard (4.2), and at least one alert rule. The cluster is
single-node minikube on a 4 GiB EC2 host that already runs the app
and Linux. The candidate has prior exposure to Prometheus + Grafana
conceptually but has not operated the stack hands-on.

The choice of how to provision Prometheus + Grafana + Alertmanager
breaks down into three shapes:

1. **Bundled Helm chart** — one install brings everything wired up.
2. **Discrete installs** — Prometheus chart + Grafana chart + manual
   wiring (datasources, scrape configs, dashboard ConfigMaps).
3. **Managed observability** — Grafana Cloud, AWS Managed Prometheus,
   etc.

The 4 GiB RAM ceiling rules out a default install of any local stack
and informs every choice that follows.

## Decision

**Install `kube-prometheus-stack` from `prometheus-community` via a
slim values profile.** The stack brings the Prometheus operator,
Prometheus, Alertmanager, Grafana, kube-state-metrics, and
node-exporter in one Helm release pinned at chart version `65.5.0`.
The candidate-authored `monitoring/values.yaml` trims:

- Prometheus to 250Mi request / 600Mi limit, 2-day retention,
  `emptyDir` TSDB (no PVC)
- Alertmanager to 32Mi / 64Mi, 24-hour retention
- Grafana to 80Mi / 192Mi, persistence off, `searchNamespace: ALL`
  for dashboard discovery
- `node-exporter`, `kube-state-metrics`, and the operator to similar
  minimal resource requests
- Scraping disabled for `kube-controller-manager`,
  `kube-scheduler`, `kube-proxy`, and `etcd` — minikube doesn't expose
  any of them

Total stack footprint lands around 700-900 MiB, leaving headroom for
the app, the gunicorn workers, and Linux.

The app chart in `charts/app/` ships its own `ServiceMonitor`,
`PrometheusRule`, and dashboard `ConfigMap` (labelled
`grafana_dashboard: "1"`) — all gated by a `monitoring.enabled`
feature flag (default `false`).

`scripts/install-monitoring.sh` wraps the install as one idempotent
command, mirroring the `scripts/deploy.sh` pattern from Day 3.4.

## Consequences

**Positive:**

- One install brings everything wired: Prometheus auto-discovers
  scrape targets via `ServiceMonitor` CRDs; Grafana auto-discovers
  dashboards via labelled `ConfigMap`s; Alertmanager auto-loads
  `PrometheusRule` CRDs. No manual datasource configuration, no
  Grafana API tokens.
- Standard, defensible architecture. The operator pattern is widely
  used in production; the case-study reviewer recognizes it without
  explanation.
- The slim profile fits the 4 GiB EC2 without crowding the app.
- The pattern extends cleanly: more apps in the cluster just add more
  `ServiceMonitor`s — no central scrape-config to edit.
- All monitoring resources live in `charts/app/templates/` next to
  the app they monitor, gated by a single flag — easy to reason about,
  easy to disable in environments without the stack.

**Negative / accepted trade-offs:**

- Heavyweight install for one Flask app: ~6 stack pods plus a
  DaemonSet for node-exporter. Bare Prometheus + Grafana would be
  fewer moving parts.
- `emptyDir` storage means TSDB resets on Prometheus pod restart. A
  rollout or eviction wipes 2 days of history. Acceptable on a demo
  cluster, not in real prod.
- Lock-in to the operator's CRDs (`ServiceMonitor`, `PrometheusRule`,
  `PodMonitor`, etc.). Migrating off later means rewriting these as
  raw Prometheus scrape config.
- Grafana's `adminPassword: admin` is hard-coded as a demo
  convenience. Access is gated by `kubectl port-forward` + SSH tunnel
  rather than exposed publicly, so this is acceptable for demo scope
  but would be unacceptable in any context where Grafana is on a
  public URL.

**Where this decision breaks down:**

- If RAM constraints tightened further (≤2 GiB ceiling), the slim
  profile would still OOM and we'd have to retreat to bare Prometheus
  with no operator.
- If observability requirements grew to include traces or logs at
  scale, the stack would need OpenTelemetry Collector + Loki + Tempo,
  which the slim profile isn't sized for.

## Alternatives considered

- **Bare Prometheus + Grafana, no operator.** Lower footprint, no
  CRDs to learn. Rejected because manual scrape-config management
  becomes the bottleneck the moment a second app needs scraping —
  the operator's selector model handles that automatically. Also a
  weaker case-study story: "I configured Prometheus manually" reads
  as less production-shaped than "I used the operator pattern".
- **Grafana Cloud (managed Prometheus + Grafana).** Free tier exists.
  Rejected because (a) the case study runs on a candidate's account
  and adding a third-party SaaS dependency complicates the demo, and
  (b) it would side-step the "install observability on Kubernetes"
  task the case study is actually testing.
- **AWS Managed Prometheus + Managed Grafana.** Stronger AWS story but
  adds significant cost (Managed Grafana ≈$9/user/month base) and
  the case study brief explicitly stays in the free-tier zone.
- **VictoriaMetrics + Grafana.** A more memory-efficient Prometheus
  drop-in. Tempting on a 4 GiB host, but it's the less-conventional
  pick — reviewer recognition of `kube-prometheus-stack` matters more
  than the marginal memory saving.

## References

- `monitoring/values.yaml` — slim profile with per-component
  rationale inline.
- `scripts/install-monitoring.sh` — install entry point.
- `charts/app/templates/{servicemonitor,prometheusrule,dashboard-configmap}.yaml`.
- `charts/app/dashboards/app-overview.json` — the dashboard JSON.
- `PROGRESS.md` Decisions #28-32 (slim profile, install script,
  monitoring-in-app-chart, dashboard provisioning, div-by-zero
  guard).
- README section "Prometheus + Grafana (Day 4.2)".
