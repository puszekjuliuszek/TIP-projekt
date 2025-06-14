#!/bin/bash

set -e

# Kolory dla outputu
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Konfiguracja
ISTIO_VERSION="${ISTIO_VERSION:-1.19.3}"
ISTIO_NAMESPACE="${ISTIO_NAMESPACE:-istio-system}"

echo -e "${GREEN}🚀 Rozpoczynam instalację Istio ${ISTIO_VERSION}...${NC}"

# Sprawdź czy klaster jest dostępny
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}❌ Błąd: Brak połączenia z klastrem Kubernetes${NC}"
    echo -e "${YELLOW}Uruchom najpierw: ./scripts/01-setup-eks.sh${NC}"
    exit 1
fi

# Sprawdzenie czy istioctl jest zainstalowane
if ! command -v istioctl &> /dev/null; then
    echo -e "${YELLOW}⚠️  istioctl nie jest zainstalowane. Instaluję...${NC}"
    
    # Pobieranie i instalacja istioctl
    cd /tmp
    curl -L https://istio.io/downloadIstio | ISTIO_VERSION=${ISTIO_VERSION} sh -
    sudo mv istio-${ISTIO_VERSION}/bin/istioctl /usr/local/bin/
    rm -rf istio-${ISTIO_VERSION}
    cd - > /dev/null
    
    echo -e "${GREEN}✅ istioctl zainstalowane${NC}"
fi

# Sprawdzenie wersji istioctl
echo -e "${GREEN}🔍 Sprawdzam wersję istioctl...${NC}"
istioctl version --remote=false

# Tworzenie konfiguracji Istio zoptymalizowanej dla testów wydajności
echo -e "${GREEN}⚙️  Tworzę konfigurację Istio...${NC}"
cat > configs/istio-config.yaml << EOF
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  name: control-plane
  namespace: ${ISTIO_NAMESPACE}
spec:
  values:
    global:
      meshID: mesh1
      network: network1
      proxy:
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
    pilot:
      resources:
        requests:
          cpu: 500m
          memory: 2048Mi
        limits:
          cpu: 1000m
          memory: 4096Mi
  components:
    pilot:
      k8s:
        resources:
          requests:
            cpu: 500m
            memory: 2048Mi
          limits:
            cpu: 1000m
            memory: 4096Mi
    ingressGateways:
    - name: istio-ingressgateway
      enabled: true
      k8s:
        service:
          type: NodePort
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
    egressGateways:
    - name: istio-egressgateway
      enabled: false
EOF

# Instalacja Istio
echo -e "${GREEN}🔧 Instaluję Istio control plane...${NC}"
kubectl create namespace ${ISTIO_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Pre-check instalacji
echo -e "${GREEN}🔍 Sprawdzam wymagania wstępne...${NC}"
istioctl x precheck

# Instalacja z customową konfiguracją
echo -e "${GREEN}⏳ Instaluję Istio (może potrwać kilka minut)...${NC}"
istioctl install -f configs/istio-config.yaml --verify -y

# Oczekiwanie na uruchomienie wszystkich komponentów
echo -e "${GREEN}⏳ Oczekuję na uruchomienie komponentów Istio...${NC}"
kubectl wait --for=condition=available deployment/istiod -n ${ISTIO_NAMESPACE} --timeout=600s
kubectl wait --for=condition=available deployment/istio-ingressgateway -n ${ISTIO_NAMESPACE} --timeout=600s

# Sprawdzenie statusu instalacji
echo -e "${GREEN}✅ Sprawdzam status instalacji Istio...${NC}"
istioctl verify-install -f configs/istio-config.yaml
kubectl get pods -n ${ISTIO_NAMESPACE}

# Włączenie automatic sidecar injection dla namespace performance-test
echo -e "${GREEN}💉 Włączam automatic sidecar injection...${NC}"
kubectl label namespace performance-test istio-injection=enabled --overwrite
kubectl label namespace default istio-injection=enabled --overwrite

# Tworzenie namespace dla aplikacji isotope
kubectl create namespace isotope --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace isotope istio-injection=enabled --overwrite

# Instalacja Prometheus dla Istio (zoptymalizowana konfiguracja)
# Zostało to przeniesione do 05-monitoring.sh dla centralizacji

# Restart deploymentów w namespace z włączonym injection
echo -e "${GREEN}🔄 Restartuję deploymenty dla wstrzyknięcia sidecar...${NC}"
kubectl rollout restart deployment/performance-test-deployment -n performance-test 2>/dev/null || echo "Deployment nie istnieje jeszcze"

# Konfiguracja telemetrii Istio
echo -e "${GREEN}📡 Konfiguruję telemetrię Istio...${NC}"
cat > configs/istio-telemetry.yaml << EOF
apiVersion: telemetry.istio.io/v1alpha1
kind: Telemetry
metadata:
  name: default-metrics
  namespace: ${ISTIO_NAMESPACE}
spec:
  metrics:
  - providers:
    - name: prometheus
  - overrides:
    - match:
        metric: ALL_METRICS
      tagOverrides:
        destination_service_name:
          value: "{{.destination_service_name | default \"unknown\"}}"
        destination_service_namespace:
          value: "{{.destination_service_namespace | default \"unknown\"}}"
        source_app:
          value: "{{.source_app | default \"unknown\"}}"
        destination_app:
          value: "{{.destination_app | default \"unknown\"}}"
---
apiVersion: telemetry.istio.io/v1alpha1
kind: Telemetry
metadata:
  name: access-logging
  namespace: ${ISTIO_NAMESPACE}
spec:
  accessLogging:
  - providers:
    - name: otel
---
# Gateway dla dostępu do aplikacji
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: performance-gateway
  namespace: ${ISTIO_NAMESPACE}
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
EOF

kubectl apply -f configs/istio-telemetry.yaml

# Sprawdzenie konfiguracji Istio
echo -e "${GREEN}🔍 Sprawdzam konfigurację Istio...${NC}"
istioctl proxy-status
istioctl analyze

# Zapisanie informacji o instalacji Istio
cat > istio-info.txt << EOF
Istio Installation Info
=======================
Version: ${ISTIO_VERSION}
Namespace: ${ISTIO_NAMESPACE}
Ingressgateway: Enabled (LoadBalancer)
Automatic injection: Enabled w namespace performance-test, isotope, default

Dostęp do metryk:
- Prometheus: kubectl port-forward -n ${ISTIO_NAMESPACE} svc/prometheus 9090:9090
- Istiod metrics: kubectl port-forward -n ${ISTIO_NAMESPACE} svc/istiod 15014:15014

Sprawdzenie statusu:
- kubectl get pods -n ${ISTIO_NAMESPACE}
- istioctl proxy-status
- istioctl analyze

Konfiguracja:
- Gateway: performance-gateway
- Telemetry: Włączona z Prometheus
- Profiling: Włączony dla Pilot

Zainstalowano: $(date)
EOF

# Pobranie informacji o LoadBalancer (jeśli dostępny)
echo -e "${GREEN}🌐 Sprawdzam adres LoadBalancer...${NC}"
LB_IP=$(kubectl get svc istio-ingressgateway -n ${ISTIO_NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Pending...")
echo "LoadBalancer address: $LB_IP" >> istio-info.txt

echo -e "${GREEN}🎉 Istio został pomyślnie zainstalowany!${NC}"
echo -e "${GREEN}📊 Status:${NC}"
echo -e "   • Control plane: $(kubectl get pods -n ${ISTIO_NAMESPACE} --no-headers | grep Running | wc -l) running pods"
echo -e "   • Sidecar injection: Enabled"
echo -e "   • LoadBalancer: $LB_IP"
echo -e "${GREEN}📁 Informacje o instalacji zapisane w istio-info.txt${NC}"
echo -e "${GREEN}➡️  Następny krok: ./scripts/04-deploy-isotope.sh${NC}" 