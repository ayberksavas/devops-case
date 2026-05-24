# RUNBOOK

> A short operator's guide for the `devops-case` deployment. Designed to
> answer the four "in an incident, what do I do?" questions: how to
> restart, where to look, how to roll back, how to rotate secrets.

For architectural context see [`README.md`](./README.md) and
[`docs/adr/`](./docs/adr/). For the security model see
[`SECURITY.md`](./SECURITY.md).

---

## At a glance

| Need to … | Command (run on EC2 unless noted) |
|---|---|
| Check if the app is healthy | `kubectl get pods -l app.kubernetes.io/name=app` |
| See recent JSON logs | `kubectl logs -l app.kubernetes.io/name=app --tail=50` |
| Restart all app pods | `kubectl rollout restart deployment/app` |
| Watch a rollout | `kubectl rollout status deployment/app` |
| Roll back to previous Helm revision | `helm rollback app` |
| List Helm revisions | `helm history app` |
| Open Grafana from laptop | `ssh -L 3000:localhost:3000 <ec2>` + `kubectl -n monitoring port-forward svc/kps-grafana 3000:80` |
| Open Prometheus from laptop | Same, port 9090 |
| Re-trigger CI deploy from scratch | `gh workflow run ci.yml --ref main` (from laptop) |

---

## 1. Restart the app

### A pod is misbehaving

```bash
kubectl get pods -l app.kubernetes.io/name=app
kubectl delete pod <name>
# Deployment immediately creates a replacement; the ReplicaSet guarantees
# the desired replica count.
```

### The deployment is wedged (all pods unhealthy)

```bash
kubectl rollout restart deployment/app
kubectl rollout status deployment/app --timeout=120s
```

`rollout restart` triggers a rolling restart without touching the image
tag — useful for picking up updated ConfigMap/Secret values (which are
checksum-annotated on the pod template, so a chart upgrade rolls them
automatically; this command is for cases where you want to force one
manually).

### Minikube itself is wedged

```bash
sudo systemctl status docker            # docker daemon must be up
minikube status
minikube stop
minikube start
minikube addons enable ingress          # idempotent; only needed if state was lost
```

After `minikube start`, the cluster's existing Deployments come back
because Kubernetes state is persisted in the minikube VM's `/var/lib`.
The kube-prometheus-stack and the app should reappear without
re-running `install-monitoring.sh` or `helm upgrade`.

---

## 2. Where to find logs

### Application logs (JSON, stdout)

```bash
# Last 50 lines from all pods
kubectl logs -l app.kubernetes.io/name=app --tail=50

# Stream a specific pod
kubectl logs -f <pod-name>

# Across both pods, structured
kubectl logs -l app.kubernetes.io/name=app --tail=100 --prefix=true \
  | grep -E '"level":"ERROR"|"status":[45][0-9]{2}'
```

Each line is a JSON object with `timestamp`, `level`, `msg`,
`request_id`, `method`, `path`, `status`, `duration_ms`. See
README §Observability.

### Grafana — dashboards & metrics

```bash
# On EC2
kubectl -n monitoring port-forward svc/kps-grafana 3000:80

# On laptop, in another shell
ssh -i ~/Downloads/devops-case.pem -L 3000:localhost:3000 -L 9090:localhost:9090 ubuntu@<eip>

# Then in browser: http://localhost:3000 (admin / admin)
# Dashboards → "App overview"
```

### Prometheus — raw queries & alerts

```bash
# Port-forwards same as above; browser to http://localhost:9090
# Alerts tab → check rule state (inactive = healthy)
# Status → Targets → verify all scrape targets are "up"
```

### CI / build / deploy logs

```bash
# From laptop with gh CLI
gh run list --workflow ci.yml --limit 5
gh run view <run-id>           # full log
gh run view <run-id> --log     # raw log dump
```

Auto-deploy stdout/stderr is captured in the `deploy (ssm → ec2 → helm)`
job; failures there mean the SSM command on EC2 failed.

---

## 3. Roll back

### Rolling back the application

```bash
# See revision history
helm history app

# Roll back to the previous revision
helm rollback app

# Or roll back to a specific revision
helm rollback app <revision-number>

# Watch the rollback
kubectl rollout status deployment/app

# Verify the deployed SHA
curl -sS -H "Host: devops-case.local" http://$(minikube ip)/version
```

`helm rollback` always creates a *new* revision pointing at the old
values — it doesn't truncate history. So rolling back from rev 5 to
rev 4 creates rev 6 with rev 4's contents. This means rollbacks are
themselves rolled-back-able.

### Rolling back the monitoring stack

```bash
helm history kps -n monitoring
helm rollback kps -n monitoring <revision>
```

In practice this rarely makes sense — the stack is mostly stateless
across upgrades and a clean reinstall is often faster:

```bash
helm uninstall kps -n monitoring
bash scripts/install-monitoring.sh
```

### Rolling back infra (Terraform/OpenTofu)

State is local on the operator's laptop (`infra/terraform.tfstate`).
There is no remote backup, so "rollback" means either:

- Reverting the relevant commit on `main` and re-running `tofu plan` /
  `apply` to bring AWS back to the previous configuration, **or**
- Restoring `terraform.tfstate` from a backup (`*.tfstate.backup` is
  written automatically by `tofu` on each apply).

For the case-study scope this is rarely needed — the live resources
predate Terraform and most edits to `infra/` are description-only.

---

## 4. Rotate a secret

### `DEMO_TOKEN` (the placeholder Helm Secret)

This is the demo Secret wired via `envFrom`. Rotation:

```bash
# On EC2
NEW_TOKEN=$(openssl rand -hex 16)
helm upgrade app charts/app -f charts/app/values-prod.yaml \
  --set-string secret.DEMO_TOKEN="$NEW_TOKEN" \
  --reuse-values
kubectl rollout status deployment/app

# Verify the rollover
kubectl get pods -l app.kubernetes.io/name=app   # new pod hashes
```

The chart's pod template has a checksum annotation on the Secret
manifest, so a Secret change triggers a rolling restart automatically.

### Grafana `admin` password

It's set in `monitoring/values.yaml` as `adminPassword: admin` for the
demo. Real rotation:

1. Update `monitoring/values.yaml` (or supply `--set` at install time).
2. `bash scripts/install-monitoring.sh` — idempotent upgrade.
3. The Grafana pod restarts and picks up the new password from its
   environment.

Caveat: Grafana stores additional users in its (ephemeral, since
`persistence.enabled=false`) sqlite DB. Restart of the Grafana pod
also wipes those — for this demo cluster, admin is the only user, so
this is benign.

### GitHub Actions OIDC role

There's no key material to rotate — the role is assumed via OIDC each
run. If the trust relationship needs to be re-issued (e.g., suspected
compromise of the role's trust policy):

1. AWS Console → IAM → Roles → `github-actions-devops-case` → edit trust.
2. Update the `aud` / `sub` conditions.
3. Optionally rotate the OIDC provider's thumbprint (the public
   GitHub Actions one is well-known).

### AWS access keys

Not applicable — this project intentionally uses **no long-lived AWS
access keys**. All authentication is either short-lived OIDC tokens
(in CI) or short-lived session tokens via `aws login` (on the
operator's laptop).

---

## 5. Common failure modes

### Public URL unreachable from outside (`curl http://<EIP>/ping` connection refused)

The cluster is up, `curl $(minikube ip)/ping` works from EC2, but the
Elastic IP doesn't serve. Cause: the host-level forwarder
(`minikube-ingress-proxy` systemd unit) isn't running. With the
docker driver, minikube doesn't bind to the host's port 80 — that's
what the forwarder bridges.

```bash
# Quick status
sudo systemctl status minikube-ingress-proxy --no-pager

# If inactive / failed:
sudo systemctl restart minikube-ingress-proxy
sudo systemctl status minikube-ingress-proxy --no-pager

# Tail logs if it keeps failing
sudo journalctl -u minikube-ingress-proxy --no-pager | tail -30
```

Common reasons for failure after a fresh boot:

- **`minikube` hasn't been started yet** — the forwarder's target
  (`192.168.49.2:80`) isn't reachable, so `socat` retries every 10s
  but can't connect. Fix: `minikube start`. Within seconds the
  forwarder's next restart attempt succeeds.
- **Minikube was deleted and recreated** — the IP may have drifted
  from `192.168.49.2`. Check with `minikube ip` and update the
  `ExecStart` line in `/etc/systemd/system/minikube-ingress-proxy.service`
  if it changed (then `daemon-reload` + `restart`).

See `SETUP.md` "Phase 4 — Host-level port forwarding" for the
full rationale and the original unit definition.

### `helm upgrade` fails with `no matches for kind "ServiceMonitor"`

The kube-prometheus-stack CRDs aren't installed yet. Install the stack
first:

```bash
bash scripts/install-monitoring.sh
```

### Auto-deploy job fails with SSM `InvalidInstanceId` or timeout

The EC2 SSM agent isn't reachable. Causes:

- EC2 is stopped (start it from the AWS console).
- SSM agent isn't running on the host (`sudo systemctl status amazon-ssm-agent` on EC2; usually auto-recovers).
- Instance profile `devops-case-ec2-ssm` was detached (rare; check
  AWS Console → EC2 → Security → IAM role).

### Grafana shows "no data" on a panel

- Prometheus might not be scraping the app. Check
  `kubectl get servicemonitor -A` — the `app` SM should be present.
- Verify scrape targets: Prometheus UI → Status → Targets — the `app`
  job should have 2 endpoints `up`.
- The metric might genuinely have no samples in the time window.
  Generate some traffic (the loop in README §"Local verification")
  and refresh.

### `kubectl` says `Unable to connect to the server`

Minikube is stopped or its kubeconfig context is wrong:

```bash
minikube status
kubectl config current-context     # should be "minikube"
kubectl config use-context minikube
```

### `tofu plan` shows unexpected drift on `aws_security_group.minikube`

Someone changed the SG via the AWS console outside Terraform. The
honest fix is either to revert the console change (so plan goes empty)
or to update `infra/main.tf` to reflect the new state and commit it.
**Don't `tofu apply` blind to reconcile back to the old config** — read
the diff first; it might be a legitimate change someone made in a
hurry.

---

## 6. Out of scope / known limitations

- **No `kubectl logs --previous` from before a pod crash on a fresh
  minikube boot.** Logs are tied to container lifetime; if you need
  post-mortem on a crashed pod, capture logs *before* deleting the
  pod.
- **Prometheus TSDB resets on Prometheus pod restart** (no PVC, by
  design — see ADR 0003).
- **No paging / on-call rotation.** Alerts go to Alertmanager but
  there's no Slack / email / PagerDuty webhook wired up. The
  `HighErrorRate` rule fires into Alertmanager only, and you'd see it
  via the Alertmanager UI or the Prometheus Alerts tab.
- **The Grafana admin password is `admin`.** Access is gated by SSH
  tunnel, not by the password — don't expose Grafana publicly without
  changing this.
