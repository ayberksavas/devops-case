# Architecture Decision Records

Lightweight ADRs documenting the load-bearing architectural choices for
this project. Format follows Michael Nygard's standard
(`Status / Context / Decision / Consequences`), trimmed to the case-study
scale (3–5 short paragraphs each).

A decision is worth a full ADR — rather than a one-line bullet in
[`../../PROGRESS.md`](../../PROGRESS.md) — when:

- the decision is architecturally significant (changing it would
  require touching multiple parts of the system), **and**
- there are meaningful alternatives that were explicitly considered.

For smaller decisions (style, library picks, environment values) see
the numbered decision log in `PROGRESS.md`.

## Records

| # | Title | Day | Summary |
|---|---|---|---|
| [0001](./0001-track-a-minikube-on-ec2.md) | Track A — Minikube on EC2 | Day 0 | Cloud EC2 over local + tunnel, for AWS exposure and a stable public URL |
| [0002](./0002-ci-push-deploy-via-oidc-ssm.md) | CI-push deploy via OIDC + SSM | Day 3.4 | Auto-deploy from GitHub Actions over GitOps (ArgoCD/Flux), reusing existing OIDC trust |
| [0003](./0003-kube-prometheus-stack.md) | Observability via kube-prometheus-stack (slim) | Day 4.2 | Operator-bundled Helm chart with a slim values profile to fit the 4 GiB EC2 |

## Conventions

- Filename: `<NNNN>-<short-kebab-title>.md`
- Status values: `Proposed`, `Accepted`, `Deprecated`, `Superseded by <NNNN>`
- An ADR is immutable once `Accepted`. If the decision changes, write a
  new ADR that supersedes the old one (and update the old one's
  `Superseded by` field) — don't edit history.
- Cross-references to `PROGRESS.md` decisions are by number (e.g.
  "Decision #25") so the smaller-grained log stays the single source of
  truth for the full list.
