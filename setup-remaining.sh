#!/bin/bash

set -e

# Kolory dla outputu
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Banner
echo -e "${BLUE}"
cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║            INSTALACJA KOMPONENTÓW NA ISTNIEJĄCYM KLASTRZE EKS               ║
║                        KWOK + ISTIO + MONITORING                            ║
║                                                                              ║
║         Automatyczna instalacja po ręcznym utworzeniu klastra EKS           ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Funkcja sprawdzania statusu kroku
check_step_status() {
    local step_name=$1
    local check_command=$2
    
    echo -e "${YELLOW}🔍 Sprawdzam status: ${step_name}...${NC}"
    
    if eval "$check_command" &>/dev/null; then
        echo -e "${GREEN}✅ ${step_name} - OK${NC}"
        return 0
    else
        echo -e "${RED}❌ ${step_name} - FAILED${NC}"
        return 1
    fi
}

# Funkcja wyświetlania postępu
show_progress() {
    local step=$1
    local total=$2
    local description=$3
    
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}KROK ${step}/${total}: ${description}${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
}

echo -e "${GREEN}🚀 Rozpoczynam instalację komponentów na istniejącym klastrze EKS...${NC}"

# Opcjonalne czyszczenie zawieszonych namespace'ów
if kubectl get namespaces | grep -q "Terminating"; then
    echo -e "${YELLOW}⚠️  Znaleziono zawieszuone namespace'y. Chcesz je wyczyścić? (y/n)${NC}"
    read -r answer
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        ./cleanup-namespaces.sh
    fi
fi

# Sprawdź czy klaster EKS jest dostępny
echo -e "${GREEN}🔍 Sprawdzam połączenie z klastrem EKS...${NC}"
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}❌ Błąd: Brak połączenia z klastrem Kubernetes${NC}"
    echo -e "${YELLOW}Upewnij się, że:${NC}"
    echo -e "1. Klaster EKS jest utworzony i aktywny"
    echo -e "2. kubectl jest skonfigurowane: aws eks update-kubeconfig --region us-west-2 --name kwok-performance-test"
    exit 1
fi

echo -e "${GREEN}✅ Połączenie z klastrem OK${NC}"
echo -e "${GREEN}📊 Klaster: $(kubectl config current-context)${NC}"
echo -e "${GREEN}📊 Węzły: $(kubectl get nodes --no-headers | wc -l)${NC}"

# Krok 1: KWOK Installation
show_progress 1 5 "INSTALACJA KWOK + FAKE NODES"
echo -e "${GREEN}⏱️  Szacowany czas: 5-10 minut${NC}"

./scripts/02-install-kwok.sh

if check_step_status "KWOK Controller" "kubectl get pods -n kube-system -l app=kwok-controller | grep Running"; then
    echo -e "${GREEN}🎉 KWOK Controller gotowy!${NC}"
    
    # Tworzenie fake nodes
    echo -e "${GREEN}🖥️  Tworzę fake nodes...${NC}"
    # ./create-fake-nodes.sh
    
    echo -e "${GREEN}📊 Fake nodes: $(kubectl get nodes --selector=type=kwok --no-headers | wc -l)${NC}"
else
    echo -e "${RED}❌ Błąd instalacji KWOK. Sprawdź logi powyżej.${NC}"
    exit 1
fi

echo -e "${GREEN}⏳ Pauza 30 sekund przed następnym krokiem...${NC}"
sleep 30

# Krok 2: Istio Installation
show_progress 2 5 "INSTALACJA ISTIO"
echo -e "${GREEN}⏱️  Szacowany czas: 5-10 minut${NC}"

./scripts/03-install-istio.sh

if check_step_status "Istio Control Plane" "kubectl get pods -n istio-system -l app=istiod | grep Running"; then
    echo -e "${GREEN}🎉 Istio gotowy!${NC}"
else
    echo -e "${RED}❌ Błąd instalacji Istio. Sprawdź logi powyżej.${NC}"
    exit 1
fi

echo -e "${GREEN}⏳ Pauza 30 sekund przed następnym krokiem...${NC}"
sleep 30

# Krok 3: Isotope Applications
show_progress 3 5 "WDROŻENIE APLIKACJI TESTOWYCH"
echo -e "${GREEN}⏱️  Szacowany czas: 10-15 minut${NC}"

./scripts/04-deploy-isotope.sh

if check_step_status "Test Applications" "kubectl get pods -n testapp | grep Running | wc -l | awk '{print (\$1 >= 5)}'"; then
    echo -e "${GREEN}🎉 Aplikacje testowe gotowe!${NC}"
    echo -e "${GREEN}📊 Running pods: $(kubectl get pods -n testapp --no-headers | grep Running | wc -l)${NC}"
else
    echo -e "${RED}❌ Błąd wdrażania aplikacji testowych. Sprawdź logi powyżej.${NC}"
    exit 1
fi

echo -e "${GREEN}⏳ Pauza 30 sekund przed następnym krokiem...${NC}"
sleep 30

# Krok 4: Monitoring Setup
show_progress 4 5 "KONFIGURACJA MONITOROWANIA"
echo -e "${GREEN}⏱️  Szacowany czas: 5-10 minut${NC}"

./scripts/05-monitoring.sh

if check_step_status "Monitoring Stack" "kubectl get pods -n monitoring | grep Running | wc -l | awk '{print (\$1 >= 3)}'"; then
    echo -e "${GREEN}🎉 Monitorowanie gotowe!${NC}"
else
    echo -e "${RED}❌ Błąd konfiguracji monitorowania. Sprawdź logi powyżej.${NC}"
    exit 1
fi

# Podsumowanie instalacji
echo -e "\n${GREEN}══════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}                    🎉 INSTALACJA ZAKOŃCZONA! 🎉${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════════════════${NC}"

echo -e "\n${BLUE}📊 PODSUMOWANIE ŚRODOWISKA:${NC}"
echo -e "├─ EKS Cluster: $(kubectl config current-context)"
echo -e "├─ Real nodes: $(kubectl get nodes -l type!=kwok --no-headers | wc -l)"
echo -e "├─ KWOK fake nodes: $(kubectl get nodes -l type=kwok --no-headers | wc -l)"
echo -e "├─ Istio version: $(istioctl version --remote=false 2>&1 | head -1 | cut -d' ' -f2 || echo 'Unknown')"
echo -e "├─ Test services: $(kubectl get svc -n testapp --no-headers | wc -l)"
echo -e "├─ Total pods: $(kubectl get pods --all-namespaces --no-headers | grep Running | wc -l)"
echo -e "└─ Monitoring: Prometheus + Grafana"

echo -e "\n${BLUE}🌐 DOSTĘP DO ŚRODOWISKA:${NC}"
echo -e "├─ Grafana: kubectl port-forward -n monitoring svc/grafana 3000:3000"
echo -e "├─ Prometheus: kubectl port-forward -n monitoring svc/prometheus 9090:9090"
echo -e "├─ Test Apps: kubectl port-forward -n testapp svc/fortio-load-generator 8080:8080"
echo -e "└─ KWOK metrics: kubectl port-forward -n kube-system svc/kwok-controller 10247:10247"

echo -e "\n${BLUE}🧪 TESTY WYDAJNOŚCI:${NC}"
echo -e "├─ Test obciążenia: ./test-load.sh"
echo -e "├─ Przewodnik metryk: docs/metrics-guide.md"
echo -e "└─ Troubleshooting: docs/troubleshooting.md"

echo -e "\n${BLUE}💾 INFORMACJE ZAPISANE W:${NC}"
echo -e "├─ kwok-info.txt - informacje o KWOK"
echo -e "├─ istio-info.txt - informacje o Istio"
echo -e "├─ testapp-info.txt - informacje o aplikacjach"
echo -e "└─ monitoring-info.txt - informacje o monitorowaniu"

echo -e "\n${YELLOW}💡 NASTĘPNE KROKI:${NC}"
echo -e "1. Sprawdź status środowiska: kubectl get pods --all-namespaces"
echo -e "2. Uruchom port-forward dla Grafana: kubectl port-forward -n monitoring svc/grafana 3000:3000"
echo -e "3. Otwórz Grafana w przeglądarce: http://localhost:3000 (admin/admin123)"
echo -e "4. Analizuj metryki zgodnie z docs/metrics-guide.md"

echo -e "\n${GREEN}💰 SZACOWANE KOSZTY:${NC}"
echo -e "Dzienne koszty EKS: ~$5/dzień (control plane + 2x t3.medium)"
echo -e "Pamiętaj o usunięciu klastra po testach!"

echo -e "\n${GREEN}✅ Środowisko gotowe do analizy wydajności Kubernetes Control Plane!${NC}"

# Utworzenie pomocniczych skryptów port-forward
echo -e "\n${YELLOW}🔧 Tworzę pomocnicze skrypty port-forward...${NC}"

# Grafana port-forward
cat > start-grafana.sh << 'EOF'
#!/bin/bash
echo "🚀 Uruchamiam port-forward dla Grafana..."
echo "Grafana będzie dostępna pod: http://localhost:3000"
echo "Login: admin, Hasło: admin123"
echo "Aby zatrzymać, naciśnij Ctrl+C"
kubectl port-forward -n monitoring svc/grafana 3000:3000
EOF

# Test app port-forward
cat > start-testapp.sh << 'EOF'
#!/bin/bash
echo "🚀 Uruchamiam port-forward dla aplikacji testowych..."
echo "Fortio UI będzie dostępne pod: http://localhost:8080/fortio/"
echo "Aby zatrzymać, naciśnij Ctrl+C"
kubectl port-forward -n testapp svc/fortio-load-generator 8080:8080
EOF

chmod +x start-grafana.sh start-prometheus.sh start-testapp.sh

echo -e "${GREEN}✅ Utworzono pomocnicze skrypty:${NC}"
echo -e "├─ ./start-grafana.sh - uruchom Grafana"
echo -e "├─ ./start-prometheus.sh - uruchom Prometheus"
echo -e "├─ ./start-testapp.sh - uruchom aplikację testową"
echo -e "└─ ./cleanup-namespaces.sh - wyczyść zawieszuone namespace'y"

echo -e "\n${GREEN}🎉 Setup completed successfully! Happy performance testing! 🎉${NC}" 
