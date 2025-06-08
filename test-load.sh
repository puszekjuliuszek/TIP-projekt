#!/bin/bash

# Sprawdź czy namespace jest podany jako argument, jeśli nie - użyj testapp
NAMESPACE=${1:-testapp}

echo "🚀 Rozpoczynam test obciążenia z Fortio w namespace: $NAMESPACE..."

# Test dostępności serwisów
echo "📊 Test dostępności serwisów..."
echo "Frontend: http://frontend.$NAMESPACE.svc.cluster.local:80"
echo "Backend: http://backend.$NAMESPACE.svc.cluster.local:80"

# Test przez load generator
echo "🎯 Uruchamiam test obciążenia..."
kubectl exec -n $NAMESPACE deployment/fortio-load-generator -- fortio load \
  -c 8 -qps 50 -t 30s -loglevel Info \
  http://frontend.$NAMESPACE.svc.cluster.local:80/

echo "📈 Test backend..."
kubectl exec -n $NAMESPACE deployment/fortio-load-generator -- fortio load \
  -c 4 -qps 25 -t 30s -loglevel Info \
  http://backend.$NAMESPACE.svc.cluster.local:80/

echo "📊 Raport z testów:"
kubectl exec -n $NAMESPACE deployment/fortio-load-generator -- fortio report

echo "✅ Test zakończony" 