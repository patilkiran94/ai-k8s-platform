#!/usr/bin/env bash
# Phase 4: build the image, load into kind, verify the node has it.
set -euo pipefail
cd "$(dirname "$0")/.."; source scripts/env.sh

docker build -t "$IMAGE" .
kind load docker-image "$IMAGE" --name "$KIND_CLUSTER"
echo ">> Images on the kind node:"
docker exec "$KIND_NODE" crictl images | grep -E "ai-api|IMAGE" || true
echo ">> Phase 4 OK"
