#!/bin/bash

set -e

# Kolory dla outputu
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Konfiguracja
KWOK_VERSION="${KWOK_VERSION:-v0.7.0}"

echo -e "${GREEN}🚀 Rozpoczynam instalację KWOK v${KWOK_VERSION}...${NC}"

# Sprawdź czy klaster jest dostępny
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}❌ Błąd: Brak połączenia z klastrem Kubernetes${NC}"
    echo -e "${YELLOW}Upewnij się, że klaster jest uruchomiony i kubectl skonfigurowane${NC}"
    exit 1
fi

# Sprawdzenie czy KWOK CLI jest zainstalowane
if ! command -v kwok &> /dev/null; then
    echo -e "${YELLOW}⚠️  KWOK CLI nie jest zainstalowane. Instaluję...${NC}"
    
    # Pobranie i instalacja kwok
    if [[ "$OSTYPE" == "darwin"* ]]; then
        ARCH="darwin-amd64"
        if [[ $(uname -m) == "arm64" ]]; then
            ARCH="darwin-arm64"
        fi
    else
        ARCH="linux-amd64"
    fi
    
    echo -e "${GREEN}📥 Pobieranie KWOK ${KWOK_VERSION} dla ${ARCH}...${NC}"
    curl -Lo kwok "https://github.com/kubernetes-sigs/kwok/releases/download/${KWOK_VERSION}/kwok-${ARCH}"
    chmod +x kwok
    
    # Próbuj zainstalować do /usr/local/bin, jeśli nie ma sudo to do ~/.local/bin
    if sudo mv kwok /usr/local/bin/ 2>/dev/null; then
        echo -e "${GREEN}✅ KWOK zainstalowany w /usr/local/bin${NC}"
    else
        echo -e "${YELLOW}⚠️  Brak uprawnień sudo, instaluję w ~/.local/bin${NC}"
        mkdir -p ~/.local/bin
        mv kwok ~/.local/bin/
        export PATH="$HOME/.local/bin:$PATH"
        echo -e "${GREEN}✅ KWOK zainstalowany w ~/.local/bin${NC}"
        echo -e "${YELLOW}💡 Dodaj ~/.local/bin do PATH w ~/.bashrc lub ~/.zshrc${NC}"
    fi
else
    echo -e "${GREEN}✅ KWOK CLI już zainstalowane: $(kwok --version)${NC}"
fi

# KWOK używa standardowy namespace kube-system
echo -e "${GREEN}📦 Używam standardowego namespace kube-system...${NC}"

# Instalacja oficjalnych KWOK CRDs i komponentów
echo -e "${GREEN}🔧 Instaluję oficjalne KWOK CRDs i komponenty...${NC}"
kubectl apply -f https://github.com/kubernetes-sigs/kwok/releases/download/${KWOK_VERSION}/kwok.yaml

# Instalacja Stage configurations
echo -e "${GREEN}🎭 Instaluję oficjalne Stage configurations...${NC}"
kubectl apply -f https://github.com/kubernetes-sigs/kwok/releases/download/${KWOK_VERSION}/stage-fast.yaml

# Dodanie uprawnień do zarządzania leases (potrzebne dla node heartbeats)
echo -e "${GREEN}🔑 Dodaję uprawnienia do zarządzania node leases...${NC}"
kubectl patch clusterrole kwok-controller --type='json' -p='[
  {
    "op": "add", 
    "path": "/rules/-", 
    "value": {
      "apiGroups": ["coordination.k8s.io"], 
      "resources": ["leases"], 
      "verbs": ["get", "list", "watch", "create", "update", "patch", "delete"]
    }
  }
]'

# Oczekiwanie na uruchomienie KWOK Controller
echo -e "${GREEN}⏳ Oczekuję na uruchomienie KWOK Controller...${NC}"
kubectl wait --for=condition=available deployment/kwok-controller -n kube-system --timeout=300s

# Sprawdzenie statusu
echo -e "${GREEN}✅ KWOK Controller uruchomiony! Sprawdzam status...${NC}"
kubectl get pods -n kube-system -l app=kwok-controller
kubectl get services -n kube-system -l app=kwok-controller

# Sprawdzenie Stage configurations
echo -e "${GREEN}📋 Sprawdzam zainstalowane Stage configurations...${NC}"
kubectl get stages

# Zapisanie informacji o instalacji KWOK
cat > kwok-info.txt << EOF
KWOK Installation Info
======================
Version: ${KWOK_VERSION}
Status: ✅ Zainstalowany i uruchomiony
Namespace: kube-system (oficjalny)

Komponenty:
✅ KWOK Controller deployment
✅ KWOK CRDs (Stage, ResourceUsage, etc.)
✅ Stage configurations (node-initialize, pod-ready, etc.)
✅ RBAC permissions (z leases)

Sprawdzenie statusu:
- kubectl get pods -n kube-system -l app=kwok-controller
- kubectl get stages

Port-forward dla metryk:
kubectl port-forward -n kube-system service/kwok-controller 10247:10247

Zainstalowano: $(date)

📚 Kolejne kroki:
1. Utwórz fake nodes: ./create-fake-nodes.sh
2. Zainstaluj Istio: ./scripts/03-install-istio.sh
3. Wdróż aplikacje: ./scripts/04-deploy-isotope.sh
4. Skonfiguruj monitoring: ./scripts/05-monitoring.sh

Lub użyj automatycznej instalacji: ./setup-remaining.sh
EOF

echo -e "${GREEN}🎉 KWOK został pomyślnie zainstalowany!${NC}"
echo -e "${GREEN}📊 Status:${NC}"
echo -e "   • Wersja: ${KWOK_VERSION}"
echo -e "   • Controller: uruchomiony w kube-system"
echo -e "   • CRDs: zainstalowane"
echo -e "   • Stages: zainstalowane"

echo -e "\n${YELLOW}📁 Informacje o instalacji zapisane w kwok-info.txt${NC}"

echo -e "\n${GREEN}🚀 Następne kroki:${NC}"
echo -e "   1. ${YELLOW}Utwórz fake nodes:${NC} ./create-fake-nodes.sh"
echo -e "   2. ${YELLOW}Zainstaluj Istio:${NC} ./scripts/03-install-istio.sh"
echo -e "   3. ${YELLOW}Lub wszystko na raz:${NC} ./setup-remaining.sh"

echo -e "\n${GREEN}💡 Testowanie:${NC}"
echo -e "   kubectl get nodes                    # Sprawdź wszystkie węzły"
echo -e "   kubectl get stages                   # Sprawdź Stage configs"
echo -e "   kubectl top nodes                    # Sprawdź metryki węzłów" 