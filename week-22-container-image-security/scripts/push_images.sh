#!/usr/bin/env bash
# Build and push the three test images.
#
# Run after the HCP apply has finished. Reads the repository URL from the
# workspace outputs rather than taking it as an argument, so there is nothing
# to copy by hand and nothing to get wrong.
#
#   bash scripts/push_images.sh
#
# Requires Docker to be running. Every base image is pinned by digest, so a
# rerun builds the same thing and the scan results in the blog post stay true.

set -euo pipefail

cd "$(dirname "$0")/.."

REGION="${AWS_REGION:-us-east-1}"
REPO_URL="${REPO_URL:-}"

if [ -z "$REPO_URL" ]; then
  echo "Reading the repository URL from Terraform outputs..."
  REPO_URL=$(cd terraform/environments/dev && terraform output -raw app_repository_url)
fi

REGISTRY="${REPO_URL%%/*}"

echo "Registry: $REGISTRY"
echo "Repository: $REPO_URL"
echo

if ! docker info >/dev/null 2>&1; then
  echo "Docker is not running. Start Docker Desktop and try again." >&2
  exit 1
fi

echo "== Authenticating to ECR =="
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"
echo

# Tag suffix keeps reruns from colliding with IMMUTABLE tags, which reject a
# second push to the same tag by design.
STAMP="$(date -u +%Y%m%d-%H%M%S)"

build_and_push() {
  local dir="$1" tag="$2"
  echo "== $tag =="
  docker build --platform linux/amd64 -t "${REPO_URL}:${tag}" "docker/${dir}"
  echo "-- pushing at $(date -u +%H:%M:%S)Z"
  docker push "${REPO_URL}:${tag}"
  echo
}

build_and_push clean    "clean-${STAMP}"
build_and_push vuln-os  "vuln-os-${STAMP}"
build_and_push vuln-lib "vuln-lib-${STAMP}"

echo "Pushed three images with suffix ${STAMP}."
echo "Now run: bash scripts/test_gate.sh ${STAMP}"
