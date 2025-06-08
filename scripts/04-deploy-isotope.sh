#!/bin/bash

set -e

# Kolory dla outputu
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Konfiguracja
ISOTOPE_VERSION="latest"
ISOTOPE_NAMESPACE="${ISOTOPE_NAMESPACE:-testapp}"
SERVICES_COUNT="${SERVICES_COUNT:-10}"
REPLICAS_PER_SERVICE="${REPLICAS_PER_SERVICE:-3}"

# Zastąpmy Isotope na Fortio - oficjalny load generator Istio
FORTIO_IMAGE="fortio/fortio:latest"

echo -e "${GREEN}🚀 Rozpoczynam wdrożenie aplikacji testowych...${NC}"

# Sprawdź czy klaster jest dostępny
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}❌ Błąd: Brak połączenia z klastrem Kubernetes${NC}"
    echo -e "${YELLOW}Uruchom najpierw wcześniejsze skrypty${NC}"
    exit 1
fi

# Sprawdź czy Istio jest zainstalowane
if ! kubectl get namespace istio-system &>/dev/null; then
    echo -e "${RED}❌ Błąd: Istio nie jest zainstalowane${NC}"
    echo -e "${YELLOW}Uruchom najpierw: ./scripts/03-install-istio.sh${NC}"
    exit 1
fi

echo -e "${GREEN}📦 Tworzę namespace isotope...${NC}"
kubectl create namespace ${ISOTOPE_NAMESPACE} 2>/dev/null || true
kubectl label namespace ${ISOTOPE_NAMESPACE} istio-injection=enabled --overwrite

echo -e "${GREEN}📥 Przygotowuję aplikacje testowe...${NC}"

# Tworzenie prostych aplikacji testowych zamiast skomplikowanej topologii
echo -e "${GREEN}🔧 Tworzę aplikacje testowe...${NC}"

# Funkcja do tworzenia prostej aplikacji HTTP
create_test_service() {
    local service_name=$1
    local replicas=$2
    local cpu_request=$3
    local memory_request=$4
    
    cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${service_name}
  namespace: ${ISOTOPE_NAMESPACE}
  labels:
    app: ${service_name}
    version: v1
spec:
  replicas: ${replicas}
  selector:
    matchLabels:
      app: ${service_name}
      version: v1
  template:
    metadata:
      labels:
        app: ${service_name}
        version: v1
    spec:
      containers:
      - name: ${service_name}
        image: nginx:alpine
        ports:
        - containerPort: 80
          name: http
        resources:
          requests:
            cpu: ${cpu_request}
            memory: ${memory_request}
          limits:
            cpu: 1000m
            memory: 1Gi
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: ${service_name}
  namespace: ${ISOTOPE_NAMESPACE}
  labels:
    app: ${service_name}
spec:
  selector:
    app: ${service_name}
  ports:
  - port: 80
    targetPort: 80
    name: http
EOF
}

# Tworzenie aplikacji testowych
echo -e "${GREEN}🏗️  Tworzę aplikacje testowe...${NC}"

create_test_service "frontend" ${REPLICAS_PER_SERVICE} "100m" "128Mi"
create_test_service "backend" ${REPLICAS_PER_SERVICE} "200m" "256Mi"
create_test_service "database" $((REPLICAS_PER_SERVICE + 1)) "300m" "512Mi"

# Load generator z Fortio
echo -e "${GREEN}⚡ Tworzę Fortio load generator...${NC}"
cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fortio-load-generator
  namespace: ${ISOTOPE_NAMESPACE}
  labels:
    app: fortio-load-generator
    version: v1
spec:
  replicas: 2
  selector:
    matchLabels:
      app: fortio-load-generator
      version: v1
  template:
    metadata:
      labels:
        app: fortio-load-generator
        version: v1
    spec:
      containers:
      - name: fortio
        image: ${FORTIO_IMAGE}
        args:
        - server
        - -http-port=8080
        - -grpc-port=8079
        - -redirect-port=8081
        ports:
        - containerPort: 8080
          name: http
        - containerPort: 8079
          name: grpc
        - containerPort: 8081
          name: redirect
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
        readinessProbe:
          httpGet:
            path: /fortio/
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /fortio/
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: fortio-load-generator
  namespace: ${ISOTOPE_NAMESPACE}
  labels:
    app: fortio-load-generator
spec:
  selector:
    app: fortio-load-generator
  ports:
  - port: 8080
    targetPort: 8080
    name: http
  - port: 8079
    targetPort: 8079
    name: grpc
EOF

# Virtual Services dla Istio routing
echo -e "${GREEN}🛣️  Konfiguruję Istio Virtual Services...${NC}"
cat > configs/isotope-virtualservices.yaml << EOF
# Frontend Virtual Service
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: frontend
  namespace: ${ISOTOPE_NAMESPACE}
spec:
  hosts:
  - frontend
  http:
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: frontend
        port:
          number: 80
    retries:
      attempts: 3
      perTryTimeout: 2s
---
# Destination Rules dla load balancing
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: frontend
  namespace: ${ISOTOPE_NAMESPACE}
spec:
  host: frontend
  trafficPolicy:
    loadBalancer:
      simple: ROUND_ROBIN
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        http1MaxPendingRequests: 50
        maxRequestsPerConnection: 10
        maxRetries: 3
        idleTimeout: 30s
    outlierDetection:
      consecutiveGatewayErrors: 5
      interval: 30s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
---
# Gateway service routing
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: gateway
  namespace: ${ISOTOPE_NAMESPACE}
spec:
  hosts:
  - gateway
  http:
  - route:
    - destination:
        host: gateway
        port:
          number: 80
---
# Database service - critical path
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: database
  namespace: ${ISOTOPE_NAMESPACE}
spec:
  host: database
  trafficPolicy:
    loadBalancer:
      simple: LEAST_CONN
    connectionPool:
      tcp:
        maxConnections: 200
      http:
        http1MaxPendingRequests: 100
        maxRequestsPerConnection: 5
        maxRetries: 2
        idleTimeout: 60s
    outlierDetection:
      consecutiveGatewayErrors: 3
      interval: 30s
      baseEjectionTime: 30s
      maxEjectionPercent: 30
EOF

kubectl apply -f configs/isotope-virtualservices.yaml

# Fortio monitoring - podstawowe metryki
echo -e "${GREEN}📊 Konfiguruję monitorowanie Fortio...${NC}"
echo "Fortio dostarcza wbudowane metryki przez /fortio/ endpoint"
echo "Fortio logs: kubectl logs -n ${ISOTOPE_NAMESPACE} deployment/fortio-load-generator"

# Oczekiwanie na uruchomienie aplikacji
echo -e "${GREEN}⏳ Oczekuję na uruchomienie aplikacji...${NC}"
echo -e "${YELLOW}To może potrwać kilka minut...${NC}"

# Sprawdzenie statusu deploymentów
services=("frontend" "backend" "database")

for service in "${services[@]}"; do
    echo -e "${YELLOW}⏳ Oczekuję na ${service}...${NC}"
    kubectl wait --for=condition=available deployment/${service} -n ${ISOTOPE_NAMESPACE} --timeout=300s
done

# Oczekiwanie na load generator
echo -e "${YELLOW}⏳ Oczekuję na load generator...${NC}"
kubectl wait --for=condition=available deployment/fortio-load-generator -n ${ISOTOPE_NAMESPACE} --timeout=300s

# Sprawdzenie statusu podów
echo -e "${GREEN}✅ Sprawdzam status wszystkich podów...${NC}"
kubectl get pods -n ${ISOTOPE_NAMESPACE}

# Test connectivity przez Istio gateway
echo -e "${GREEN}🔗 Testuję połączenie przez Istio gateway...${NC}"
GATEWAY_IP=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "localhost")
echo "Gateway IP/hostname: $GATEWAY_IP"

# Tworzenie skryptu do testowania obciążenia z Fortio
cat > test-load.sh << 'EOF'
#!/bin/bash
echo "🚀 Rozpoczynam test obciążenia z Fortio..."

# Test dostępności serwisów
echo "📊 Test dostępności serwisów..."
echo "Frontend: http://frontend.${ISOTOPE_NAMESPACE}.svc.cluster.local:80"
echo "Backend: http://backend.${ISOTOPE_NAMESPACE}.svc.cluster.local:80"
echo "Database: http://database.${ISOTOPE_NAMESPACE}.svc.cluster.local:80"

# Test przez load generator
echo "🎯 Uruchamiam test obciążenia..."
kubectl exec -n ${ISOTOPE_NAMESPACE} deployment/fortio-load-generator -- fortio load \
  -c 8 -qps 50 -t 30s -loglevel Info \
  http://frontend.${ISOTOPE_NAMESPACE}.svc.cluster.local:80/

echo "📈 Test backend..."
kubectl exec -n ${ISOTOPE_NAMESPACE} deployment/fortio-load-generator -- fortio load \
  -c 4 -qps 25 -t 30s -loglevel Info \
  http://backend.${ISOTOPE_NAMESPACE}.svc.cluster.local:80/

echo "📊 Raport z testów:"
kubectl exec -n ${ISOTOPE_NAMESPACE} deployment/fortio-load-generator -- fortio report

echo "✅ Test zakończony"
EOF

chmod +x test-load.sh

# Zapisanie informacji o wdrożeniu
cat > testapp-info.txt << EOF
Test Applications Deployment Info
==================================
Namespace: ${ISOTOPE_NAMESPACE}
Services: $(kubectl get svc -n ${ISOTOPE_NAMESPACE} --no-headers | wc -l)
Deployments: $(kubectl get deployment -n ${ISOTOPE_NAMESPACE} --no-headers | wc -l)
Total Pods: $(kubectl get pods -n ${ISOTOPE_NAMESPACE} --no-headers | wc -l)

Główne serwisy:
- frontend (entry point)
- backend (backend service)
- database (storage)

Load Generator: 2 replicas, 50 RPS, 10 connections

Dostęp:
- Przez LoadBalancer: http://${GATEWAY_IP}/
- Port-forward: kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80

Monitorowanie:
- kubectl get pods -n ${ISOTOPE_NAMESPACE}
- kubectl logs -n ${ISOTOPE_NAMESPACE} deployment/fortio-load-generator
- ./test-load.sh

Metryki:
- kubectl port-forward -n ${ISOTOPE_NAMESPACE} svc/fortio-load-generator 8080:8080
- curl http://localhost:8080/fortio/

Dostęp do Fortio UI:
- kubectl port-forward -n ${ISOTOPE_NAMESPACE} svc/fortio-load-generator 8080:8080
- Otwórz: http://localhost:8080/fortio/

Wdrożono: $(date)
EOF

echo -e "${GREEN}🎉 Aplikacje testowe zostały pomyślnie wdrożone!${NC}"
echo -e "${GREEN}📊 Status:${NC}"
echo -e "   • Namespace: ${ISOTOPE_NAMESPACE}"
echo -e "   • Serwisy: $(kubectl get svc -n ${ISOTOPE_NAMESPACE} --no-headers | wc -l)"
echo -e "   • Pody: $(kubectl get pods -n ${ISOTOPE_NAMESPACE} --no-headers | wc -l)"
echo -e "   • Load Generator: Aktywny"
echo -e "${GREEN}📁 Informacje o wdrożeniu zapisane w testapp-info.txt${NC}"
echo -e "${GREEN}🧪 Uruchom test: ./test-load.sh${NC}"
echo -e "${GREEN}➡️  Następny krok: ./scripts/05-monitoring.sh${NC}" 