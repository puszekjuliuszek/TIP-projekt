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
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
PROMETHEUS_PID=$!

echo "📈 Prometheus dostępny pod: http://localhost:9090"

# Test skalowania dla sprawdzenia wydajności
echo "🔧 Rozpoczynam test skalowania aplikacji isotope..."

# Skalowanie deploymentów
for deployment in frontend gateway auth productcatalog cart payment database cache recommendation; do
    echo "📈 Skaluję $deployment do 10 replik..."
    kubectl scale deployment $deployment -n isotope --replicas=10
done

echo "⏳ Oczekuję 30 sekund na stabilizację..."
sleep 30

# Sprawdzenie metryk
echo "📊 Sprawdzam kluczowe metryki wydajności:"

echo "1. API Server Request Latency (99th percentile):"
curl -s "http://localhost:9090/api/v1/query?query=histogram_quantile(0.99,%20rate(apiserver_request_duration_seconds_bucket{verb!=\"WATCH\"}[5m]))" | jq -r '.data.result[0].value[1] // "N/A"' | xargs -I {} echo "   {} seconds"

echo "2. etcd Request Latency (99th percentile):"
curl -s "http://localhost:9090/api/v1/query?query=histogram_quantile(0.99,%20rate(etcd_request_duration_seconds_bucket[5m]))" | jq -r '.data.result[0].value[1] // "N/A"' | xargs -I {} echo "   {} seconds"

echo "3. Scheduler Queue Depth:"
curl -s "http://localhost:9090/api/v1/query?query=scheduler_pending_pods" | jq -r '.data.result[0].value[1] // "N/A"' | xargs -I {} echo "   {} pods"

echo "4. Current Running Pods:"
kubectl get pods --all-namespaces --no-headers | grep Running | wc -l | xargs -I {} echo "   {} pods"

echo "5. KWOK Fake Nodes:"
kubectl get nodes --selector=type=kwok --no-headers | wc -l | xargs -I {} echo "   {} nodes"

echo "6. Istio Pilot Push Time (99th percentile):"
curl -s "http://localhost:9090/api/v1/query?query=histogram_quantile(0.99,%20rate(pilot_xds_push_time_bucket[5m]))" | jq -r '.data.result[0].value[1] // "N/A"' | xargs -I {} echo "   {} seconds"

# Skalowanie w dół
echo "📉 Skaluję z powrotem do początkowej liczby replik..."
for deployment in frontend gateway auth productcatalog cart payment database cache recommendation; do
    kubectl scale deployment $deployment -n isotope --replicas=3
done

echo "✅ Test wydajności zakończony!"
echo "📊 Sprawdź dashboardy Grafana: $GRAFANA_URL"
echo "📈 Sprawdź metryki Prometheus: http://localhost:9090"

# Cleanup port-forwards
cleanup() {
    if [ ! -z "$GRAFANA_PID" ]; then
        kill $GRAFANA_PID 2>/dev/null || true
    fi
    if [ ! -z "$PROMETHEUS_PID" ]; then
        kill $PROMETHEUS_PID 2>/dev/null || true
    fi
}

echo "💡 Aby zatrzymać port-forwards, naciśnij Ctrl+C"
trap cleanup EXIT

# Czekaj na Ctrl+C
wait
