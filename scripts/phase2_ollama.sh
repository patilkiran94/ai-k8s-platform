#!/usr/bin/env bash
# Phase 2: install Ollama on the Ubuntu host, bind it to the kind bridge only,
# pull a small model and test inference.
set -euo pipefail
cd "$(dirname "$0")"; source ./env.sh

if ! command -v ollama >/dev/null; then
  curl -fsSL https://ollama.com/install.sh | sh
fi

GW="$(kind_gateway || true)"
if [ -z "$GW" ]; then
  echo "!! docker network 'kind' not found - is the kind cluster created? Binding to 127.0.0.1 only."
  echo "   Pods won't reach Ollama until you re-run this script after creating the cluster."
  BIND="127.0.0.1"
else
  BIND="$GW"
  SUBNET="$(kind_subnet)"
  # Allow only the kind subnet to reach Ollama if ufw is active.
  if command -v ufw >/dev/null && sudo ufw status | grep -q "Status: active"; then
    sudo ufw allow from "$SUBNET" to "$GW" port 11434 proto tcp comment 'kind->ollama'
  fi
fi

# Listen on the docker bridge gateway IP (not 0.0.0.0) => not exposed to your LAN.
sudo mkdir -p /etc/systemd/system/ollama.service.d
sudo tee /etc/systemd/system/ollama.service.d/override.conf >/dev/null <<CONF
[Service]
Environment="OLLAMA_HOST=${BIND}:11434"
CONF
sudo systemctl daemon-reload
sudo systemctl enable --now ollama
sudo systemctl restart ollama
sleep 3

export OLLAMA_HOST="${BIND}:11434"
echo ">> Pulling ${MODEL_NAME}"
ollama pull "$MODEL_NAME"

echo ">> Inference API test"
curl -s "http://${BIND}:11434/api/generate" \
  -d "{\"model\":\"${MODEL_NAME}\",\"prompt\":\"Say hello in five words.\",\"stream\":false}" \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print("RESPONSE:", d["response"].strip())'
echo ">> Phase 2 OK (Ollama on ${BIND}:11434)"
