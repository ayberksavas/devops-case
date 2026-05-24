# ADR 0001 — Track A: Minikube on EC2

**Status:** Accepted (2026-05-20)

**Supersedes:** none

**Superseded by:** none

## Context

The case study offers two implementation tracks:

- **Track A — Minikube on EC2.** A single-node Kubernetes cluster running on
  an AWS free-tier EC2 instance, with the app exposed through an Elastic
  IP and the security group.
- **Track B — Local minikube + tunnel.** Minikube on the candidate's
  laptop, with the app exposed to the internet via ngrok or cloudflared.

Both tracks lead to the same end-to-end deliverable. The choice changes the
character of the project: cloud exposure and IAM practice (Track A) vs.
faster iteration with no cloud cost (Track B).

The candidate has prior experience with Linux + Docker but limited
hands-on AWS exposure. The project is also used as a portfolio piece, so
demonstrable cloud infrastructure is a benefit beyond the case-study
grading itself.

## Decision

**Track A — Minikube on EC2 in `eu-north-1`** (Stockholm), on a
`c7i-flex.large` instance (2 vCPU, 4 GiB RAM, free-tier eligible),
Ubuntu 26.04 LTS, 20 GiB gp3 root volume. Elastic IP attached for a
stable public endpoint. Security group restricts SSH to the candidate's
home `/32`; opens 80, 443, and the NodePort range (30000-32767) to the
world.

Subsequent work codifies this surface in OpenTofu (see ADR 0002 for the
deploy path that depends on it).

## Consequences

**Positive:**

- AWS hands-on practice: EC2 lifecycle, security groups, Elastic IPs,
  IAM roles + OIDC federation, SSM agent + send-command, instance
  profiles.
- A stable public URL on a fixed IP — convenient for sharing the demo
  and verifying CI deploys against a known target.
- Forces real consideration of IAM scoping, network exposure, and
  long-running cost — which the local-tunnel path would not.
- IaC story is meaningful (Day 4.3 codifies the live infrastructure in
  OpenTofu); Track B would have substituted a `Makefile`, which is a
  weaker exercise.

**Negative / accepted trade-offs:**

- AWS account and free-tier responsibilities — billing alerts and the
  instance lifecycle are now part of the operational cost.
- Slower iteration on infra changes (instance start/stop, terraform
  plan/apply, EBS provisioning) vs. local minikube which is "delete and
  recreate".
- 4 GiB RAM ceiling on the chosen free-tier-eligible instance constrains
  Day 4.2 observability — drives the slim `kube-prometheus-stack`
  profile (ADR 0003) and the multiprocess metrics pattern (decision #25
  in `PROGRESS.md`).
- Bonus IaC option (codifying IAM in Terraform too) was scoped out at
  Day 4.3; would have been simpler on Track B by virtue of having no
  cloud IAM to codify.

## Alternatives considered

- **Track B (local minikube + cloudflared/ngrok tunnel).** Faster setup
  (≈15 minutes), zero cloud cost, simpler. Rejected because the case
  study's stated grading criteria value cloud awareness equally to
  Track A, *and* because the candidate explicitly wanted AWS exposure
  as a portfolio outcome.
- **A larger EC2 instance (e.g., `t3.large`).** Would have removed the
  4 GiB headroom pressure but disqualified the project from
  free-tier billing. Rejected — the constraint is a feature (drives
  thoughtful resource tuning) rather than a problem.
- **Managed Kubernetes (EKS).** Closer to "real prod" but out of free
  tier and far beyond case-study scope.

## References

- `SETUP.md` — Day 0 infrastructure log with the exact instance type,
  AMI, and security-group rules.
- `PROGRESS.md` Decision #1 (track choice), #2 (instance type), #3
  (security group scoping).
- `infra/` — OpenTofu config codifying this surface (Day 4.3).
