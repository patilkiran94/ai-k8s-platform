#!/usr/bin/env bash
# Phase 7: functional, latency, concurrency tests + cluster inspection.
set -euo pipefail
cd "$(dirname "$0")/.."; source scripts/env.sh

NODE_IP="$(docker inspect -f '{{.NetworkSettings.Networks.kind.IPAddress}}' "$KIND_NODE")"
URL="http://${NODE_IP}:${API_NODEPORT}"

echo ">> Single request"
curl -s -w '\nHTTP %{http_code}  total %{time_total}s\n' "$URL/generate" \
  -H 'Content-Type: application/json' \
  -d '{"prompt":"What is Prometheus used for?","max_tokens":80}'

echo; echo ">> Bad request (expect 422)"
curl -s -o /dev/null -w 'HTTP %{http_code}\n' "$URL/generate" -H 'Content-Type: application/json' -d '{}'

echo; echo ">> Sequential load (10 req, concurrency 1)"
python3 scripts/load_test.py "$URL" 10 1
echo; echo ">> Concurrent load (20 req, concurrency 5)"
python3 scripts/load_test.py "$URL" 20 5

echo; echo ">> Pods / resource usage"
kubectl -n "$NS_APP" get pods -o wide
kubectl top pods -n "$NS_APP" 2>/dev/null || echo "(metrics-server not installed - use Grafana CPU/memory panels)"
echo; echo ">> Last logs"
kubectl -n "$NS_APP" logs deploy/ai-api --tail=15
echo; echo ">> Host CPU/memory (Ollama does the heavy lifting)"
free -h | head -2; ps -C ollama -o pid,%cpu,%mem,rss,cmd | head -3 || true
