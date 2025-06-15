#!/bin/bash

echo "🚀 Rozpoczynam testy wydajności Kubernetes Control Plane..."

# Pobierz adres LoadBalancer Grafana
GRAFANA_IP=$(kubectl get svc grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
if [ -z "$GRAFANA_IP" ]; then
    echo "⚠️  Grafana LoadBalancer nie jest gotowy, używam port-forward..."
    kubectl port-forward -n monitoring svc/grafana 3000:3000 &
    GRAFANA_PID=$!
    GRAFANA_URL="http://localhost:3000"
else
    GRAFANA_URL="http://$GRAFANA_IP:3000"
fi

echo "📊 Grafana dostępna pod: $GRAFANA_URL (admin/admin123)"

# Port-forward dla Prometheus
PROMETHEUS_IP=$(kubectl get svc prometheus -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
if [ -z "$PROMETHEUS_IP" ]; then
    echo "⚠️  Prometheus LoadBalancer nie jest gotowy, używam port-forward..."
    kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
    PROMETHEUS_PID=$!
    PROMETHEUS_URL="http://localhost:9090"
else
    PROMETHEUS_URL="http://$PROMETHEUS_IP:9090"
fi

echo "📈 Prometheus dostępny pod: $PROMETHEUS_URL"

# Test skalowania dla sprawdzenia wydajności
echo "🔧 Rozpoczynam test skalowania aplikacji isotope..."

# Konfiguracja
ISOTOPE_NAMESPACE="${ISOTOPE_NAMESPACE:-testapp}"
GRAFANA_URL="$GRAFANA_URL"
PROMETHEUS_URL="$PROMETHEUS_URL"

cleanup() {
    echo "🧹 Czyszczenie po teście..."
    # Przywracanie pierwotnej liczby replik
    scale_app frontend 1
    scale_app gateway 1
    scale_app auth 1
    scale_app productcatalog 1
    scale_app cart 1
    scale_app payment 1
    scale_app database 1
    scale_app cache 1
    kill $PROMETHEUS_PID
    kill $GRAFANA_PID
}

trap cleanup EXIT

scale_app() {
    echo "📈 Skaluję $1 do $2 replik..."
    kubectl scale deployment/$1 --replicas=$2 -n ${ISOTOPE_NAMESPACE} || echo "⚠️  Nie udało się przeskalować $1"
}

# Skalowanie w górę
APPS="frontend gateway auth productcatalog cart payment database cache"
for app in $APPS; do
    scale_app $app 10
    sleep 5 # Krótka pauza między skalowaniem
done

# Czekaj na ustabilizowanie się metryk
echo "⏳ Czekam 60 sekund na ustabilizowanie się metryk..."
sleep 60

echo "📊 Sprawdzam kluczowe metryki wydajności:"

echo "1. API Server Request Latency (99th percentile):"
curl -s "$PROMETHEUS_URL/api/v1/query?query=histogram_quantile(0.99,%20rate(apiserver_request_duration_seconds_bucket{verb!=\"WATCH\"}[5m]))" | jq -r '.data.result[0].value[1] // "N/A"' | xargs -I {} echo "   {} seconds"

echo "2. etcd Request Latency (99th percentile):"
curl -s "$PROMETHEUS_URL/api/v1/query?query=histogram_quantile(0.99,%20rate(etcd_request_duration_seconds_bucket[5m]))" | jq -r '.data.result[0].value[1] // "N/A"' | xargs -I {} echo "   {} seconds"

echo "3. Scheduler Queue Depth:"
curl -s "$PROMETHEUS_URL/api/v1/query?query=scheduler_pending_pods" | jq -r '.data.result[0].value[1] // "N/A"' | xargs -I {} echo "   {} pods"

echo "4. Current Running Pods:"
kubectl get pods --all-namespaces --no-headers | grep Running | wc -l | xargs -I {} echo "   {} pods"

echo "5. Current KWOK Nodes:"
kubectl get nodes --selector=type=kwok --no-headers | wc -l | xargs -I {} echo "   {} nodes"

echo "6. Istio Pilot Push Time (99th percentile):"
curl -s "$PROMETHEUS_URL/api/v1/query?query=histogram_quantile(0.99,%20rate(pilot_xds_push_time_bucket[5m]))" | jq -r '.data.result[0].value[1] // "N/A"' | xargs -I {} echo "   {} seconds"

# Skalowanie w dół
echo "📉 Skaluję z powrotem do początkowej liczby replik..."
for app in $APPS; do
    scale_app $app 1
done

echo "✅ Test wydajności zakończony!"
echo "📊 Sprawdź dashboardy Grafana: $GRAFANA_URL"
echo "📈 Sprawdź metryki Prometheus: $PROMETHEUS_URL"
