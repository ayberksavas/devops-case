#!/usr/bin/env bash
#
# Deploy a specific image tag to the minikube cluster on this EC2 host.
# Invoked from CI via SSM after a push to main (see .github/workflows/ci.yml).
#
# Usage: bash scripts/deploy.sh <image-tag>
#
# Expects:
#   - Running as the `ubuntu` user (kubeconfig + minikube context live in /home/ubuntu)
#   - The repo checked out at the current working directory (the SSM command cd's here)
#   - The image already pushed to GHCR by the build job

set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <image-tag>" >&2
    exit 1
fi

IMAGE_TAG="$1"
IMAGE_REPO="ghcr.io/ayberksavas/devops-case-app"
CHART_DIR="charts/app"

echo "==> Deploying ${IMAGE_REPO}:${IMAGE_TAG}"

helm upgrade --install app "${CHART_DIR}" \
    -f "${CHART_DIR}/values-prod.yaml" \
    --set image.repository="${IMAGE_REPO}" \
    --set image.tag="${IMAGE_TAG}" \
    --set config.BUILD_SHA="${IMAGE_TAG}" \
    --wait \
    --timeout 2m

echo "==> Rollout status:"
kubectl rollout status deployment/app --timeout=120s

echo
echo "Deployed ${IMAGE_REPO}:${IMAGE_TAG}"
