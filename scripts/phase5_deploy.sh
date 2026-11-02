#!/usr/bin/env bash
# Phase 5: deploy the AI API into namespace ai-platform.
set -euo pipefail
cd "$(dirname "$0")/.."; source scripts/env.sh

OLLAMA_IP="$(kind_gateway)"; export OLLAMA_IP MODEL_NAME IMAGE API_NODEPORT
[ -n "$OLLAMA_IP" ] || { echo "kind docker network not found"; exit 1; }

mkdir -p k8s/.rendered
for f in 00-namespace 10-ollama-host 20-configmap 30-deployment 40-service; do
  envsubst < "k8s/$f.yaml" > "k8s/.rendered/$f.yaml"
  kubectl apply -f "k8s/.rendered/$f.yaml"
done

kubectl -n "$NS_APP" rollout status deploy/ai-api --timeout=180s
kubectl -n "$NS_APP" get pods,svc,endpoints

NODE_IP="$(docker inspect -f '{{.NetworkSettings.Networks.kind.IPAddress}}' "$KIND_NODE")"
echo ">> NodePort test: http://${NODE_IP}:${API_NODEPORT}/health"
curl -s "http://${NODE_IP}:${API_NODEPORT}/health"; echo
