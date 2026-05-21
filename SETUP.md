# Infrastructure Setup — Day 1 Progress Log

## Overview

This document covers the infrastructure decisions and setup steps completed on Day 1 of the InsiderOne DevOps internship case study (Track A — Cloud).

---

## Track Choice: Track A (Minikube on EC2)

**Decision:** Track A was chosen over Track B (local + tunnel).

**Reasoning:** Track A provides hands-on AWS exposure — EC2, security groups, Elastic IPs — which is directly relevant to real-world DevOps work. The additional setup overhead (~45–60 minutes compared to Track B's ~15 minutes) is worth the learning value. Both tracks are evaluated equally by InsiderOne, so the choice was made purely based on what would be more educational.

---

## Phase 1 — AWS Account & Key Pair

- Created an AWS free tier account.
- Generated an EC2 key pair (`devops-case.pem`) using RSA format.
- Downloaded the `.pem` file and applied correct permissions locally:

```bash
chmod 400 devops-case.pem
```

**Why:** The `.pem` file is required for SSH access to the EC2 instance. The `chmod 400` ensures only the owner can read it — SSH rejects keys with open permissions.

---

## Phase 2 — EC2 Instance

**Instance type chosen:** `c7i-flex.large` (2 vCPU, 4 GiB RAM)

**Reasoning:** `t2.micro` and `t3.micro` only provide 1 GiB RAM, which is insufficient for minikube (minimum 2 GiB required). `c7i-flex.large` was the available free-tier-eligible option with 4 GiB RAM and 2 vCPUs — enough to run minikube comfortably alongside the application.

**AMI:** Ubuntu 26.04 LTS (amd64)

**Storage:** 20 GiB gp3

**Reasoning for 20 GiB:** The default 8 GiB fills up quickly once Docker starts pulling images and minikube spins up its internal components. 20 GiB provides comfortable headroom for the entire 4-day project.

### Security Group Rules

| Port | Protocol | Source | Reason |
|------|----------|--------|--------|
| 22 | TCP | My IP only (`/32`) | SSH — restricted to a single IP as per security best practices |
| 80 | TCP | 0.0.0.0/0 | HTTP traffic for the app |
| 443 | TCP | 0.0.0.0/0 | HTTPS traffic |
| 30000–32767 | TCP | 0.0.0.0/0 | Kubernetes NodePort range |

**Why restrict SSH to My IP:** The case study safety notes explicitly flag SSH open to the world (`0.0.0.0/0`) as an anti-pattern. Restricting to a single known IP is the correct production approach.

### Elastic IP

An Elastic IP was allocated and associated with the instance.

**Why:** EC2 instances get a new public IP on every restart by default. An Elastic IP is a static public IP that stays attached to the instance regardless of reboots, which is required for a stable public URL (`http://<EIP>:<port>`).

---

## Phase 3 — Software Installation on EC2

All commands were run after SSHing into the instance:

```bash
ssh -i devops-case.pem ubuntu@<elastic-ip>
```

### System update

```bash
sudo apt-get update && sudo apt-get upgrade -y
```

### Docker

```bash
sudo apt-get install -y docker.io
sudo usermod -aG docker $USER
newgrp docker
```

**Why Docker:** minikube requires a container runtime. Docker is the most widely supported and familiar option. Adding the user to the `docker` group avoids needing `sudo` for every Docker command.

**Verified with:**
```bash
docker run hello-world
```

### kubectl

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

**Verified:** `v1.36.1` with Kustomize `v5.8.1`

**Why kubectl:** The standard CLI for interacting with Kubernetes clusters. Required to inspect pods, services, deployments, and run rollout commands throughout the project.

### minikube

```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
minikube start --driver=docker --cpus=2 --memory=3500mb
```

**Why minikube:** Provides a single-node Kubernetes environment that runs inside Docker on the EC2 instance. No need for a managed cluster (EKS) or multi-node setup — a Deployment, Service, and Ingress is all this project needs.

**Why `--driver=docker`:** The Docker driver runs the minikube node as a Docker container, which is the recommended approach when Docker is already installed and the user is not root.

**Why `--memory=3500mb`:** Leaves ~500 MB headroom on the 4 GiB instance for the OS and other processes, while giving minikube enough memory to run the app and later Prometheus + Grafana.

**Verified:**
```bash
kubectl get nodes
# NAME       STATUS   ROLES           AGE   VERSION
# minikube   Ready    control-plane   86s   v1.35.1
```

### Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

**Why Helm:** The case study requires packaging the app as a Helm chart for Day 2. Helm is the Kubernetes package manager — it handles templating, environment-specific values (`values-dev.yaml` vs `values-prod.yaml`), and rollback (`helm rollback`). It is a production standard.

---

## Current Status

| Component | Status |
|-----------|--------|
| EC2 instance | ✅ Running |
| Elastic IP | ✅ Associated |
| Security group | ✅ Configured |
| Docker | ✅ Installed & verified |
| kubectl | ✅ v1.36.1 |
| minikube | ✅ Running (1 node, Ready) |
| Helm | ✅ Installed |

**Next step:** Write the HTTP service (Day 1 — Task 1.1).
