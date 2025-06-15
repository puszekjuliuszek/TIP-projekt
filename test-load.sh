#!/bin/bash

# Konfiguracja
ISOTOPE_NAMESPACE="${ISOTOPE_NAMESPACE:-testapp}"
GATEWAY_URL=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "localhost")

echo "🚀 Rozpoczynam test obciążenia z Fortio..."

# Sprawdzenie dostępności serwisów
echo "📊 Test dostępności serwisów..."
echo "Frontend: http://frontend.${ISOTOPE_NAMESPACE}.svc.cluster.local:80"
echo "Backend: http://backend.${ISOTOPE_NAMESPACE}.svc.cluster.local:80"
echo "Database: http://database.${ISOTOPE_NAMESPACE}.svc.cluster.local:80"

# Znalezienie poda Fortio
FORTIO_POD=$(kubectl get pods -n ${ISOTOPE_NAMESPACE} -l app=fortio-load-generator -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$FORTIO_POD" ]; then
    echo "❌ Błąd: Nie znaleziono poda Fortio load generator w namespace ${ISOTOPE_NAMESPACE}."
    exit 1
fi

echo "🎯 Uruchamiam test obciążenia..."
kubectl exec ${FORTIO_POD} -n ${ISOTOPE_NAMESPACE} -c fortio -- fortio load -qps 10 -t 60s -c 5 "http://frontend.${ISOTOPE_NAMESPACE}.svc.cluster.local:80"

echo "📈 Test backend..."
kubectl exec ${FORTIO_POD} -n ${ISOTOPE_NAMESPACE} -c fortio -- fortio load -qps 5 -t 30s -c 3 "http://backend.${ISOTOPE_NAMESPACE}.svc.cluster.local:80"

echo "📊 Raport z testów:"
kubectl exec ${FORTIO_POD} -n ${ISOTOPE_NAMESPACE} -c fortio -- fortio report

echo "✅ Test zakończony"
