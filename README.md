# Local AI Platform on Kubernetes (kind) — Ollama + FastAPI + Prometheus + Grafana

A small, fully local LLM platform: a FastAPI service on a **kind** cluster calls
**Ollama** running on the Ubuntu host, and is observed with
**kube-prometheus-stack** (Prometheus + Grafana).

## Architecture

```
Ubuntu host
├── Ollama  (systemd, listens ONLY on the kind docker-bridge gateway IP:11434)
│     └── small model (default: qwen2.5:0.5b)
└── Docker
    ├── Snipe-IT, MariaDB (unrelated, untouched)
    └── kind cluster
        ├── ns ai-platform:  ai-api (2 replicas, NodePort 30080)
        │                    └─ Service "ollama-host" ──► host bridge IP:11434
        └── ns monitoring:   Prometheus, Grafana (ServiceMonitor scrapes /metrics)
```

**Security:** Ollama is bound to the docker bridge gateway (e.g. `172.18.0.1`),
not `0.0.0.0`, so it is unreachable from your LAN. If `ufw` is active, only the
kind subnet is allowed to reach it. The API container runs as non-root with all
capabilities dropped.

## Prerequisites (Phase 1)
Docker, `kind` cluster running (default name `kind`), `kubectl`, `helm`,
`envsubst` (`sudo apt install gettext-base`), `python3-venv`, `curl`.
Another cluster name? `export KIND_CLUSTER=<name>` first.

## Run it
```bash
./scripts/phase2_ollama.sh        # install Ollama, pull model, test inference
./scripts/phase3_local_test.sh    # run the API locally, test /health /generate /metrics
./scripts/phase4_build.sh         # docker build + kind load
./scripts/phase5_deploy.sh        # namespace, deployment, service, probes, NodePort
GRAFANA_PASSWORD='choose-one' ./scripts/phase6_monitoring.sh
./scripts/phase7_test.sh          # latency, concurrency, logs, resource usage
```
Change model: `MODEL_NAME=llama3.2:1b ./scripts/phase2_ollama.sh` then re-run phases 5 (config).

## API
| Endpoint | Purpose |
|---|---|
| `GET /live` | liveness (process up) |
| `GET /health` | readiness (Ollama reachable + model present) |
| `POST /generate` | `{"prompt": "...", "max_tokens": 128, "temperature": 0.7}` |
| `GET /metrics` | Prometheus metrics |

```bash
NODE_IP=$(docker inspect -f '{{.NetworkSettings.Networks.kind.IPAddress}}' kind-control-plane)
curl -s http://$NODE_IP:30080/generate -H 'Content-Type: application/json' \
  -d '{"prompt":"Hello!","max_tokens":50}'
```
If you created the cluster with `extraPortMappings` for 30080, use `localhost:30080`.

## Metrics
`ai_api_requests_total{endpoint,method,status}`, `ai_api_request_duration_seconds` (histogram),
`ai_api_in_flight`, `ai_generate_tokens_total{type}`, `ai_ollama_errors_total{reason}`.
The "AI API Performance" Grafana dashboard is provisioned automatically.

## Access Prometheus / Grafana
```bash
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090
```
Grafana: http://localhost:3000 (admin / your password). Prometheus targets: http://localhost:9090/targets.

## Troubleshooting
```bash
kubectl -n ai-platform get pods,svc,endpoints
kubectl -n ai-platform describe pod -l app=ai-api
kubectl -n ai-platform logs deploy/ai-api --tail=50
kubectl -n ai-platform get endpoints ollama-host        # must show the bridge IP
kubectl -n ai-platform run t --rm -it --image=curlimages/curl --restart=Never -- \
    curl -s http://ollama-host:11434/api/tags             # pod -> host Ollama
docker exec kind-control-plane crictl images | grep ai-api
sudo systemctl status ollama; journalctl -u ollama -n 50
ss -ltnp | grep 11434                                      # bound to bridge IP?
kubectl -n monitoring get servicemonitor,pods
```
| Symptom | Likely cause / fix |
|---|---|
| Pod `ErrImagePull` | Image not in kind: re-run phase 4; never use `:latest` tag |
| Pod not Ready, `/health` 503 | Ollama not reachable (ufw / wrong bind IP) or model not pulled |
| Bridge IP changed after recreating cluster | Re-run phase 2 then phase 5 |
| Target missing in Prometheus | `kubectl get servicemonitor -n ai-platform`; Service port must be named `http` |
| Dashboard missing | `kubectl -n monitoring get cm -l grafana_dashboard=1`, restart Grafana pod |
| 504 from `/generate` | CPU-bound model; lower `max_tokens` or raise `REQUEST_TIMEOUT` |

## Cleanup
```bash
kubectl delete ns ai-platform; helm -n monitoring uninstall monitoring; kubectl delete ns monitoring
sudo systemctl disable --now ollama   # optional
```

## Roadmap
v2: run Ollama inside Kubernetes, add HPA, request queueing, auth on the API.
