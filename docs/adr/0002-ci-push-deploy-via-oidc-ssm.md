# ADR 0002 — CI-push deploy via OIDC + SSM (not GitOps)

**Status:** Accepted (2026-05-23, Day 3.4)

**Supersedes:** none

**Superseded by:** none

## Context

After Day 3.3 the project has a GHCR-published image tagged with the
merge commit SHA. The remaining 3.4 task is to wire a continuous-deploy
step so a merge to `main` lands the new image on the minikube cluster
without a human running `helm upgrade` by hand.

Two architecturally distinct shapes are available:

1. **CI-push** — the GitHub Actions workflow itself initiates the
   deploy, talking to AWS via OIDC-federated short-lived credentials.
2. **GitOps** — a controller running *inside* the cluster (ArgoCD or
   Flux) watches the git repo and pulls changes when manifests update.

The cluster is single-node minikube on a 4 GiB EC2 host running one
Flask app. The repo's CI already has the OIDC trust relationship
established with AWS (Day 3.2) for the `aws sts get-caller-identity`
proof job.

## Decision

**CI-push deploy via OIDC-federated `aws ssm send-command`.** The
deploy job in `.github/workflows/ci.yml` assumes the existing
`github-actions-devops-case` IAM role and uses SSM Run-Command to
invoke `bash scripts/deploy.sh <short-sha>` on the EC2 host. The
script does `git fetch && reset --hard origin/main` against
`/opt/devops-case` and then `helm upgrade --install` with
`--set image.tag=<short-sha>` and `--set config.BUILD_SHA=<short-sha>`.

The same OIDC role gets one additional inline policy (`DeployViaSSM`)
granting `ssm:SendCommand` scoped to `AWS-RunShellScript` and the EC2
instance ARN, plus `ssm:GetCommandInvocation`. No new long-lived
credentials. No GitOps controller deployed on the cluster.

## Consequences

**Positive:**

- Re-uses existing infrastructure: the OIDC trust relationship from
  Day 3.2 is extended with one inline policy; no new auth surface.
- Zero additional pods on the 4 GiB EC2 host — every megabyte goes to
  the app and the observability stack (ADR 0003), neither of which has
  room to spare.
- Tight feedback loop: merge to `main` → ≈30 seconds → new image
  running. ArgoCD's default sync interval would add minutes.
- The deploy job's stdout / stderr lands in the GitHub Actions log,
  giving a single source of truth for "what did the deploy do?"
- Helm release history makes `helm rollback` a one-command revert.

**Negative / accepted trade-offs:**

- Imperative model: the cluster's truth lives in Helm release state,
  not in the git repo. To inspect "what's deployed?" you query Helm,
  not git. ArgoCD's declarative model would make the live state
  always equal a specific commit.
- Manual rollback path: `helm rollback app` rather than "revert the
  commit and let the controller reconcile". Less elegant, more
  effective at this scale.
- SSH connectivity required from EC2 to GitHub (for the `git fetch`
  side) — already true for the existing checkout at `/opt/devops-case`,
  but it's a dependency.
- Doesn't scale to multiple apps / multiple teams without re-introducing
  the toil GitOps was designed to remove.

**Where this decision breaks down:**

The right shape changes if any of these become true:

- More than ≈3-5 apps share the cluster (the CI sprawl gets ugly).
- Multiple teams ship to the cluster (per-app deploy jobs become
  political).
- Drift between "what's deployed" and "what's in git" becomes a
  recurring debugging cost.

If any of those happen, the migration path is clear: install ArgoCD,
point an ApplicationSet at the `charts/` directory, retire the deploy
job. The Helm chart structure built in Day 2 is GitOps-ready.

## Alternatives considered

- **ArgoCD with an ApplicationSet for `dev` and `prod`** — the
  textbook GitOps answer. Rejected for this scale: ~500 MiB of
  control-plane pods on a 4 GiB host, plus an `Application` CR to
  manage per environment, for marginal benefit on a one-app
  single-node cluster. Becomes the right answer the moment the cluster
  grows past "one app, one node".
- **Flux** — same shape as ArgoCD with a smaller footprint and no UI.
  Same rejection reasoning, slightly weakened.
- **kubectl set image from CI directly** (bypass SSM, kubectl over a
  public API). Requires exposing the kubeconfig to CI somehow —
  either long-lived `KUBECONFIG` secret in GitHub (anti-pattern) or
  reaching the apiserver over the public internet (extra exposure on
  the security group). SSM avoids both: AWS-managed channel, no
  kubeconfig in CI.
- **Manual deploy after merge.** Rejected — the case study explicitly
  asks for auto-deploy on merge.

## References

- `.github/workflows/ci.yml` — the `deploy (ssm → ec2 → helm)` job.
- `scripts/deploy.sh` — the script SSM invokes on the EC2 host.
- `PROGRESS.md` Decisions #23 (this choice) and #24 (instance profile +
  inline policy details).
- README section "Auto-deploy on merge" — the operational walkthrough.
