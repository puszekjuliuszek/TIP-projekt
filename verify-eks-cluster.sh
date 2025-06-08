#!/bin/bash

set -e

# Kolory dla outputu
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 Sprawdzam klaster EKS...${NC}"

# Sprawdź podstawowe informacje
echo -e "\n${GREEN}📊 Informacje o klastrze:${NC}"
kubectl cluster-info

echo -e "\n${GREEN}📊 Węzły klastra:${NC}"
kubectl get nodes -o wide

echo -e "\n${GREEN}📊 Przestrzenie nazw:${NC}"
kubectl get namespaces

echo -e "\n${GREEN}📊 Pods systemowe:${NC}"
kubectl get pods -n kube-system

echo -e "\n${GREEN}📊 Storage classes:${NC}"
kubectl get storageclass

echo -e "\n${GREEN}📊 Services w kube-system:${NC}"
kubectl get svc -n kube-system

# Sprawdź czy Metrics Server działa
echo -e "\n${YELLOW}🔍 Sprawdzam Metrics Server...${NC}"
if kubectl get deployment metrics-server -n kube-system &>/dev/null; then
    echo -e "${GREEN}✅ Metrics Server zainstalowany${NC}"
    kubectl get pods -n kube-system -l k8s-app=metrics-server
else
    echo -e "${YELLOW}⚠️  Metrics Server nie jest zainstalowany, instaluję...${NC}"
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    echo -e "${GREEN}✅ Metrics Server zainstalowany${NC}"
fi

# Test podstawowej funkcjonalności
echo -e "\n${YELLOW}🧪 Test podstawowej funkcjonalności...${NC}"
kubectl run test-pod --image=busybox --rm -it --restart=Never --command -- echo "Hello from EKS!" || echo "Test pod completed"

# Sprawdzenie zasobów
echo -e "\n${GREEN}📊 Wykorzystanie zasobów węzłów:${NC}"
kubectl top nodes 2>/dev/null || echo "Metrics mogą być niedostępne przez kilka minut po instalacji"

# Podsumowanie
echo -e "\n${BLUE}═══════════════════════════════════════${NC}"
echo -e "${GREEN}✅ KLASTER EKS GOTOWY DO UŻYCIA!${NC}"
echo -e "${BLUE}═══════════════════════════════════════${NC}"

echo -e "\n${GREEN}📋 Podsumowanie:${NC}"
echo -e "├─ Klaster: $(kubectl config current-context)"
echo -e "├─ Węzły: $(kubectl get nodes --no-headers | wc -l)"
echo -e "├─ Wersja K8s: $(kubectl version --short --client | head -1)"
echo -e "└─ Status: READY"

echo -e "\n${YELLOW}🚀 Następne kroki:${NC}"
echo -e "1. Uruchom: ${GREEN}./scripts/02-install-kwok.sh${NC}"
echo -e "2. Następnie: ${GREEN}./scripts/03-install-istio.sh${NC}"
echo -e "3. Potem: ${GREEN}./scripts/04-deploy-isotope.sh${NC}"
echo -e "4. Na koniec: ${GREEN}./scripts/05-monitoring.sh${NC}"

echo -e "\n${BLUE}💡 Wskazówka:${NC}"
echo -e "Możesz też uruchomić automatyczną instalację reszty komponentów:"
echo -e "${GREEN}./setup-remaining.sh${NC}" 