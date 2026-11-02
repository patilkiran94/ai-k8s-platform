#!/usr/bin/env bash
# Phase 6: kube-prometheus-stack + ServiceMonitor + Grafana dashboard.
set -euo pipefail
cd "$(dirname "$0")/.."; source scripts/env.sh

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo update >/dev/null

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace "$NS_MON" --create-namespace \
  -f monitoring/values.yaml \
  --set grafana.adminPassword="$GRAFANA_PASSWORD" \
  --wait --timeout 10m

kubectl apply -f k8s/50-servicemonitor.yaml

kubectl -n "$NS_MON" create configmap ai-api-dashboard \
  --from-file=ai-api-dashboard.json=monitoring/ai-api-dashboard.json \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS_MON" label configmap ai-api-dashboard grafana_dashboard=1 --overwrite

cat <<MSG

>> Phase 6 OK. Access (run each in its own terminal):
   kubectl -n $NS_MON port-forward svc/monitoring-grafana 3000:80
       -> http://localhost:3000   user: admin   password: \$GRAFANA_PASSWORD
   kubectl -n $NS_MON port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090
       -> http://localhost:9090/targets  (look for ai-platform/ai-api)
MSG
