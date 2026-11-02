#!/usr/bin/env bash
# Phase 3: run the FastAPI app locally (venv) against host Ollama and test it.
set -euo pipefail
cd "$(dirname "$0")/.."; source scripts/env.sh

python3 -m venv .venv
. .venv/bin/activate
pip install -q -r app/requirements.txt

GW="$(kind_gateway || echo 127.0.0.1)"
export OLLAMA_URL="http://${GW}:11434" MODEL_NAME
(cd app && uvicorn main:app --port 8000 >/tmp/ai-api-local.log 2>&1 & echo $! >/tmp/ai-api-local.pid)
trap 'kill $(cat /tmp/ai-api-local.pid) 2>/dev/null || true' EXIT
sleep 3

echo ">> /live";    curl -s localhost:8000/live; echo
echo ">> /health";  curl -s localhost:8000/health; echo
echo ">> /generate"
curl -s localhost:8000/generate -H 'Content-Type: application/json' \
  -d '{"prompt":"Explain Kubernetes in one sentence.","max_tokens":60}' | python3 -m json.tool
echo ">> /metrics (ai_*)"; curl -s localhost:8000/metrics | grep '^ai_' | head -20
