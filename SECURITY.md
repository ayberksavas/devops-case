# SECURITY

> Security posture and threat model for the `devops-case` deployment.
> The scope is "a personal demo with cloud exposure", not a production
> service — but the controls below reflect what *would* extend to a
> production engagement, with the gaps called out.

---

## Reporting a vulnerability

If you find a security issue in this codebase or its deployed
infrastructure:

1. **Do not** open a public GitHub issue.
2. Open a private security advisory via GitHub:
   `Security` tab → `Report a vulnerability` on the
   [repository page](https://github.com/ayberksavas/devops-case).
3. If GitHub's private advisories aren't usable for any reason, contact
   the repository owner via their GitHub profile.

You can expect an acknowledgement within a few business days. There's
no bounty (this is a personal project), but credit is offered in the
relevant fix's release notes if you'd like it.

---

## Threat model summary

The asset is the Flask app served from `https?://<ec2-eip>/`. The
threats considered, ordered by likelihood:

1. **Credential leakage from the repo** (mitigated by §1, §2 below)
2. **Unauthorised AWS API actions** via the CI deploy path (mitigated
   by §3)
3. **Vulnerable dependencies shipped in the container image**
   (mitigated by §4)
4. **Network exposure beyond intended ports** (mitigated by §5)
5. **Privilege escalation inside the pod** (mitigated by §6)

Explicitly **out of scope** at this stage:

- DDoS resistance (no rate limiting, no CDN)
- Authn/authz at the app layer (the app is anonymous-read by design)
- Database security (there is no database)
- Multi-tenancy isolation (single user, single cluster)
- Compliance frameworks (SOC2, PCI, GDPR data subject rights)

---

## 1. Secret handling

### What's in the repo

- `.env.example` — example env vars (`PORT`, `BUILD_SHA`), no real
  values.
- `infra/terraform.tfvars.example` — placeholder `ami_id` and
  `ssh_allowed_cidr`. Real values live in `infra/terraform.tfvars`
  which is gitignored.
- `monitoring/values.yaml` — Grafana `adminPassword: admin` (demo
  only — access is gated by SSH tunnel, not by this password; see §5).

### What is *not* in the repo

- No AWS access keys (long-lived or otherwise). Day 3.2 federated
  GitHub Actions to AWS via OIDC; Day 4.3 used short-lived session
  tokens from `aws login` for the operator's laptop.
- No real `.env` file (`.env` is gitignored).
- No real `terraform.tfvars`. No `terraform.tfstate`.
- No `*.pem`, `*.key`, or SSH private keys.

### Enforcement

- `gitleaks` runs in CI on every PR and push with `fetch-depth: 0`
  (full history) and `--redact`. Currently passes. See
  README §"Secret & vulnerability scanning".
- A manual privacy sweep done at Day 4.3 (see PROGRESS Decision #38
  context) confirmed no AWS account IDs, real IPs, or AWS resource
  IDs in tracked files. The earlier exposure of the AWS account ID
  (introduced via PR #7) was scrubbed in the Day 4.3 docs round; the
  historical leak on the `main` branch's git log is an accepted
  artifact of the demo scope.

### Gaps acknowledged

- **No automated PII / metadata-leak detection.** `gitleaks` is a
  credential scanner; it doesn't catch identifiers like AWS account
  IDs or local filesystem paths. A custom gitleaks ruleset or a
  separate pre-commit hook would close this gap for a production
  engagement.

---

## 2. Authentication & authorisation

### GitHub Actions → AWS

The CI workflow assumes the `github-actions-devops-case` IAM role via
OIDC federation. The trust policy is scoped to
`repo:ayberksavas/devops-case:*` (any branch / ref). The role has two
inline policies attached:

- (implicit) `sts:GetCallerIdentity` — works without any explicit
  policy; used by the `aws OIDC (whoami)` job as a federation proof.
- `DeployViaSSM` — `ssm:SendCommand` scoped to one document
  (`AWS-RunShellScript`) and one instance (the EC2 host's ARN), plus
  `ssm:GetCommandInvocation` for status polling.

**No long-lived AWS access keys exist anywhere.** Every CI deploy
exchanges a fresh OIDC token for short-lived session credentials.

### Operator → AWS (laptop)

The operator's laptop uses AWS CLI v2's root-user login flow
(`aws login`). Session tokens live in `~/.aws/login/` and expire
within hours. There are no long-lived access keys in
`~/.aws/credentials`.

**Caveat:** the operator's laptop authenticates as the AWS account's
**root user**, not as a least-privilege IAM user. For a production
engagement this would be replaced by an IAM user or SSO identity
with permissions scoped to only what the operator needs (EC2 read,
SSM read, IAM read-only). For the demo scope, root is accepted with
the trade-off documented here.

### EC2 → AWS (instance profile)

The EC2 host has the `devops-case-ec2-ssm` instance profile attached,
carrying only the AWS-managed `AmazonSSMManagedInstanceCore` policy
(SSM agent registration). It does **not** have permission to call
`ec2:DescribeInstances` or any other broader API — credentials from
the instance metadata service can't, for example, modify the host's
own security group.

### App layer

The Flask app has no authn/authz. All endpoints are public:

- `/ping`, `/healthz`, `/version` are intentionally anonymous-read.
- `/metrics` is not behind authn either, but is only reachable on the
  pod-internal port `:8080`. The `Service` exposes the app port to
  the cluster, and the `Ingress` is configured for path `/` — so
  external requests *can* hit `/metrics` over the public ingress.
  Production hardening would either move `/metrics` to a separate
  port not exposed via Ingress, or add an annotation-based block on
  the Ingress.

---

## 3. Network exposure

### Inbound (security group)

| Port | Source | Purpose |
|---|---|---|
| 22 | Operator's home `/32` | SSH from operator only |
| 80 | `0.0.0.0/0` | HTTP via the nginx Ingress |
| 443 | `0.0.0.0/0` | HTTPS (no TLS termination yet — port is open but unused; reserved for cert-manager) |
| 30000–32767 | `0.0.0.0/0` | Kubernetes NodePort range (used for occasional direct service exposure) |

**SSH is never opened to the world.** The case-study brief explicitly
calls this out as a red flag.

The NodePort range being open is a Day 0 default that became less
necessary once the nginx Ingress was wired (Day 2). Tightening it
(closing 30000–32767 or restricting to the operator's IP) is a
follow-up that wouldn't break anything currently running.

### Outbound

The security group's egress rule allows all (`0.0.0.0/0`, all
protocols). EC2 needs outbound for:

- GitHub clones (`git fetch origin`)
- Container pulls from `ghcr.io`
- AWS API calls (SSM, EC2 metadata)
- Ubuntu package updates
- Helm chart downloads from `prometheus-community`

Tightening egress to specific endpoints is possible but expensive
maintenance for a personal project.

---

## 4. Supply chain

### Image scanning

`Trivy` runs in CI on every PR / merge / tag. Configuration:

- Failures gated on `CRITICAL` and `HIGH` severity
- `--ignore-unfixed` (CVEs without fixes don't block — they'd never
  pass otherwise)
- Trivy installed as a pinned binary (`v0.70.0`), not via the wrapper
  action (see PROGRESS Decision #17 for the rationale — the wrapper
  action's sparse-checkout pattern flakes on hosted runners).

### Image signing / SBOM

**Not implemented.** The case study lists `cosign` / SBOM / multi-arch
as bonus items; explicitly deferred (PROGRESS Decision §Day 3.5 skip).
For a production engagement, the upgrade path is:

- `cosign sign` in CI on tag push, against a Sigstore Fulcio
  certificate from the OIDC identity.
- `syft` or `trivy sbom` to produce a CycloneDX/SPDX SBOM, attached
  as an OCI artifact alongside the image.
- Admission policy (Kyverno / OPA Gatekeeper) rejecting unsigned
  images.

### Base image

`python:3.12-slim` (Debian-slim). Chosen over `distroless` for
debuggability (slim ships a shell), over `alpine` for libc consistency
(musl gotchas with C-extension wheels). Trivy is clean against this
base at the current pin.

Upgrade path documented in PROGRESS Open Questions: move to
distroless when the Trivy results justify it.

---

## 5. Pod security

### Non-root, no privilege escalation

The Dockerfile creates a `appuser` (uid 1000, `/usr/sbin/nologin`) and
the container `USER` directive switches to it. The Helm chart's
`securityContext` enforces this at the Kubernetes layer:

```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
```

If someone later swaps in a root-running image, Kubernetes refuses to
schedule the pod.

### Capability dropping

All Linux capabilities are dropped (`drop: [ALL]`). The pod has no
`CAP_NET_BIND_SERVICE`, no `CAP_SYS_PTRACE`, nothing — it can do
exactly what a uid-1000 process inside the container can do on
unprivileged syscalls.

### Secrets in pods

`DEMO_TOKEN` is delivered via Kubernetes Secret + `envFrom`, not via a
`COPY` in the Dockerfile or a hardcoded value. The Secret is supplied
at deploy time:

```bash
helm upgrade ... --set-string secret.DEMO_TOKEN=$(openssl rand -hex 16)
```

The Secret manifest in the chart has an empty default, so a missing
`--set-string` would deploy an empty token rather than a chart-baked
value. (The app doesn't currently consume `DEMO_TOKEN` — it's there
to demonstrate the wiring.)

### NetworkPolicy

**Not implemented** — listed as Day 2 bonus, intentionally skipped
(PROGRESS Decision #15). On a single-node single-app cluster the
practical benefit is minimal; on a multi-tenant or multi-app cluster
it would be required.

---

## 6. Quick verification

Run this on EC2 to confirm the basic security posture matches what
this doc claims:

```bash
# Container runs as appuser
kubectl exec -it <app-pod> -- id
# expect: uid=1000(appuser) gid=1000 ...

# Container has no extra capabilities
kubectl exec -it <app-pod> -- grep CapEff /proc/1/status
# expect: 0000000000000000

# SSH is not world-open
aws ec2 describe-security-groups --group-ids <sg-id> \
  --query "SecurityGroups[].IpPermissions[?ToPort==\`22\`].IpRanges"
# expect: a single /32, not 0.0.0.0/0

# CI's gitleaks scan is green on the latest commit
gh run list --workflow ci.yml --limit 1
```

---

## 7. Roadmap (production hardening)

Not done; called out for honesty. Roughly in priority order:

1. Replace root-user AWS access with a least-privilege IAM identity.
2. Tighten NodePort 30000-32767 egress (close the range or limit
   source to operator IP).
3. Implement `cosign` image signing + `syft` SBOM in CI.
4. Add admission policy rejecting unsigned images (Kyverno).
5. Move `/metrics` off the public Ingress (separate Service port or
   Ingress block).
6. Wire Alertmanager to a real notification channel (Slack webhook).
7. Set a real Grafana admin password and consider OIDC SSO if the
   stack moves beyond demo scope.
8. Add a `NetworkPolicy` if a second workload joins the cluster.
9. Move Terraform state to S3 + DynamoDB lock (only relevant in a
   team setting).
