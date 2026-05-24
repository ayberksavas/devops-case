#!/usr/bin/env bash
#
# Install or upgrade kube-prometheus-stack on the minikube cluster.
#
# Idempotent — re-running with the same chart version is a no-op (helm
# upgrade --install). Pinned chart version lets us bump deliberately
# rather than tracking the upstream's tip.
#
# Usage:   bash scripts/install-monitoring.sh
# Override pin: CHART_VERSION=66.0.0 bash scripts/install-monitoring.sh

set -euo pipefail

CHART_VERSION="${CHART_VERSION:-65.5.0}"
NAMESPACE="${NAMESPACE:-monitoring}"
RELEASE="${RELEASE:-kps}"
REPO_NAME="prometheus-community"
REPO_URL="https://prometheus-community.github.io/helm-charts"
VALUES_FILE="monitoring/values.yaml"

if [ ! -f "${VALUES_FILE}" ]; then
    echo "Run this from the repo root: ${VALUES_FILE} not found." >&2
    exit 1
fi

echo "==> Ensuring helm repo ${REPO_NAME} is present"
helm repo add "${REPO_NAME}" "${REPO_URL}" >/dev/null 2>&1 || true
helm repo update "${REPO_NAME}" >/dev/null

echo "==> Ensuring namespace ${NAMESPACE} exists"
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing/upgrading ${RELEASE} (chart version ${CHART_VERSION})"
helm upgrade --install "${RELEASE}" "${REPO_NAME}/kube-prometheus-stack" \
    --namespace "${NAMESPACE}" \
    --version "${CHART_VERSION}" \
    -f "${VALUES_FILE}" \
    --wait \
    --timeout 5m

echo
echo "==> Stack pods in ${NAMESPACE}:"
kubectl -n "${NAMESPACE}" get pods

cat <<'EOF'

Done. Useful follow-ups:

  # Grafana UI (admin / admin)
  kubectl -n monitoring port-forward svc/kps-grafana 3000:80

  # Prometheus UI
  kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 9090:9090

  # Alertmanager UI
  kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-alertmanager 9093:9093
EOF
