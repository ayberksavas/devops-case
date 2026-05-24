#!/usr/bin/env bash
#
# Import existing live AWS resources (created manually in Day 0) into
# Terraform/OpenTofu local state. After import, `terraform plan` should say
# "No changes" — that's the proof the .tf describes reality faithfully.
#
# Idempotent: re-running on already-imported resources is a no-op (the tool
# will say "Resource already managed by Terraform").
#
# Pre-requisites (on the host running this script):
#   - terraform or tofu in PATH
#   - AWS credentials usable by the provider (env vars, profile, or instance
#     role). Default region picks up from infra/variables.tf (eu-north-1).
#   - infra/terraform.tfvars filled in (copy from terraform.tfvars.example)
#   - `terraform init` has already been run from infra/
#
# Usage (from repo root):
#   EC2_INSTANCE_ID=i-xxx EIP_ALLOC=eipalloc-xxx SG_ID=sg-xxx \
#     bash scripts/terraform-import.sh
#
# Find the IDs with:
#   aws ec2 describe-instances --filters 'Name=tag:Name,Values=devops-case-minikube' \
#       --query 'Reservations[].Instances[].InstanceId'
#   aws ec2 describe-addresses --query 'Addresses[].AllocationId'
#   aws ec2 describe-security-groups --group-names devops-case-sg \
#       --query 'SecurityGroups[].GroupId'

set -euo pipefail

TF_BIN="${TF_BIN:-}"
if [ -z "${TF_BIN}" ]; then
    if command -v tofu >/dev/null 2>&1; then
        TF_BIN="tofu"
    elif command -v terraform >/dev/null 2>&1; then
        TF_BIN="terraform"
    else
        echo "Neither 'tofu' nor 'terraform' found in PATH." >&2
        exit 1
    fi
fi

INFRA_DIR="$(cd "$(dirname "$0")/../infra" && pwd)"

require_env() {
    local name="$1"
    if [ -z "${!name:-}" ]; then
        echo "Required env var ${name} is not set." >&2
        echo "Usage: EC2_INSTANCE_ID=i-xxx EIP_ALLOC=eipalloc-xxx SG_ID=sg-xxx $0" >&2
        exit 1
    fi
}

require_env EC2_INSTANCE_ID
require_env EIP_ALLOC
require_env SG_ID

cd "${INFRA_DIR}"

echo "==> Using ${TF_BIN} in $(pwd)"

import_or_skip() {
    local address="$1"
    local id="$2"
    if ${TF_BIN} state show "${address}" >/dev/null 2>&1; then
        echo "    ${address} already imported — skipping"
    else
        ${TF_BIN} import "${address}" "${id}"
    fi
}

echo "==> Importing EC2 instance ${EC2_INSTANCE_ID}"
import_or_skip aws_instance.minikube "${EC2_INSTANCE_ID}"

echo "==> Importing Elastic IP ${EIP_ALLOC}"
import_or_skip aws_eip.minikube "${EIP_ALLOC}"

# Note: the EIP-to-instance association is NOT a separate Terraform resource
# here. We declare it via the `network_interface` attribute on aws_eip
# directly, because aws_eip_association has a known import regression for
# VPC EIPs ("with the retirement of EC2-Classic standard domain EC2 EIPs are
# no longer supported"). Binding via network_interface avoids that path
# entirely and keeps the import flow to 3 resources.

echo "==> Importing security group ${SG_ID}"
import_or_skip aws_security_group.minikube "${SG_ID}"

echo
echo "==> Imports complete. Run:"
echo "      cd infra && ${TF_BIN} plan"
echo
echo "    Expected output: 'No changes. Your infrastructure matches the configuration.'"
echo "    Any diff means a value in .tf doesn't match live; adjust and re-plan."
echo "    NEVER run '${TF_BIN} apply' against a non-empty plan without reading it."
