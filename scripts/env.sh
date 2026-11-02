#!/usr/bin/env bash
# Shared settings. Override by exporting before running a script.
export KIND_CLUSTER="${KIND_CLUSTER:-kind}"
export MODEL_NAME="${MODEL_NAME:-qwen2.5:0.5b}"
export IMAGE="${IMAGE:-ai-api:0.1.0}"
export NS_APP="ai-platform"
export NS_MON="monitoring"
export API_NODEPORT="30080"
export GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-change-me-please}"
export KIND_NODE="${KIND_CLUSTER}-control-plane"

# IPv4 gateway of the docker network that kind uses (reachable from pods).
kind_gateway() {
  docker network inspect kind -f '{{range .IPAM.Config}}{{println .Gateway}}{{end}}' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n1
}
kind_subnet() {
  docker network inspect kind -f '{{range .IPAM.Config}}{{println .Subnet}}{{end}}' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/' | head -n1
}
