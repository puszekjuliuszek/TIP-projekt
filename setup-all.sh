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
║                    KUBERNETES CONTROL PLANE PERFORMANCE                     ║
║                         KWOK + ISTIO + EKS PROJECT                          ║
║                                                                              ║
║  Automatyczna instalacja środowiska do analizy wydajności control plane     ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Funkcja sprawdzania wymagań
check_requirements() {
    echo -e "${GREEN}🔍 Sprawdzam wymagania wstępne...${NC}"
    
    local requirements_met=true
    
    # AWS CLI
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}❌ AWS CLI nie jest zainstalowane${NC}"
        requirements_met=false
    else
        echo -e "${GREEN}✅ AWS CLI: $(aws --version 2>&1 | head -1)${NC}"
    fi
    
    # Git
    if ! command -v git &> /dev/null; then
        echo -e "${RED}❌ Git nie jest zainstalowany${NC}"
        requirements_met=false
    else
        echo -e "${GREEN}✅ Git: $(git --version)${NC}"
    fi
    
    # curl
    if ! command -v curl &> /dev/null; then
        echo -e "${RED}❌ curl nie jest zainstalowany${NC}"
        requirements_met=false
    else
        echo -e "${GREEN}✅ curl zainstalowany${NC}"
    fi
    
    # jq (opcjonalne, ale przydatne)
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}⚠️  jq nie jest zainstalowane (opcjonalne, przydatne do testów)${NC}"
        if [[ "$OSTYPE" == "darwin"* ]] && command -v brew &> /dev/null; then
            echo -e "${YELLOW}Instaluję jq...${NC}"
            brew install jq
        fi
    else
        echo -e "${GREEN}✅ jq zainstalowany${NC}"
    fi
    
    # Sprawdź AWS credentials
    if aws sts get-caller-identity &>/dev/null; then
        local identity=$(aws sts get-caller-identity --output text --query 'Arn')
        echo -e "${GREEN}✅ AWS Credentials: $identity${NC}"
    else
        echo -e "${RED}❌ AWS Credentials nie są skonfigurowane${NC}"
        echo -e "${YELLOW}Uruchom: aws configure${NC}"
        requirements_met=false
    fi
    
    if [ "$requirements_met" = false ]; then
        echo -e "${RED}❌ Nie wszystkie wymagania są spełnione. Przerwam instalację.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Wszystkie wymagania spełnione!${NC}"
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

# Funkcja pytająca o kontynuację
ask_continue() {
    local message=$1
    echo -e "\n${YELLOW}${message}${NC}"
    read -p "Czy chcesz kontynuować? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Instalacja przerwana przez użytkownika.${NC}"
        exit 0
    fi
}

# Funkcja czekania na user input
wait_for_user() {
    local message=${1:-"Naciśnij Enter aby kontynuować..."}
    echo -e "\n${YELLOW}${message}${NC}"
    read -p ""
}

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

# Główna funkcja instalacji
main() {
    echo -e "${GREEN}🚀 Rozpoczynam pełną instalację środowiska...${NC}"
    
    # Sprawdź wymagania
    check_requirements
    
    # Konfiguracja
    echo -e "\n${BLUE}📋 KONFIGURACJA PROJEKTU${NC}"
    echo -e "Region AWS: ${AWS_REGION:-us-west-2}"
    echo -e "Nazwa klastra: ${CLUSTER_NAME:-kwok-performance-test}"
    echo -e "Typ instancji: ${INSTANCE_TYPE:-m5.large}"
    echo -e "Liczba fake nodes: ${FAKE_NODES_COUNT:-100}"
    
    ask_continue "Czy konfiguracja jest poprawna?"
    
    # Krok 1: EKS Setup
    show_progress 1 5 "INSTALACJA KLASTRA EKS"
    echo -e "${GREEN}⏱️  Szacowany czas: 15-20 minut${NC}"
    ask_continue "To najdłuższy krok. Czy chcesz rozpocząć instalację EKS?"
    
    ./scripts/01-setup-eks.sh
    
    if check_step_status "EKS Cluster" "kubectl cluster-info"; then
        echo -e "${GREEN}🎉 EKS klaster gotowy!${NC}"
    else
        echo -e "${RED}❌ Błąd instalacji EKS. Sprawdź logi powyżej.${NC}"
        exit 1
    fi
    
    wait_for_user "EKS gotowy. Naciśnij Enter aby kontynuować z KWOK..."
    
    # Krok 2: KWOK Installation
    show_progress 2 5 "INSTALACJA KWOK"
    echo -e "${GREEN}⏱️  Szacowany czas: 5-10 minut${NC}"
    
    ./scripts/02-install-kwok.sh
    
    if check_step_status "KWOK Controller" "kubectl get pods -n kwok-system -l app=kwok-controller | grep Running"; then
        echo -e "${GREEN}🎉 KWOK gotowy!${NC}"
        echo -e "${GREEN}📊 Fake nodes: $(kubectl get nodes --selector=type=kwok --no-headers | wc -l)${NC}"
    else
        echo -e "${RED}❌ Błąd instalacji KWOK. Sprawdź logi powyżej.${NC}"
        exit 1
    fi
    
    wait_for_user "KWOK gotowy. Naciśnij Enter aby kontynuować z Istio..."
    
    # Krok 3: Istio Installation
    show_progress 3 5 "INSTALACJA ISTIO"
    echo -e "${GREEN}⏱️  Szacowany czas: 5-10 minut${NC}"
    
    ./scripts/03-install-istio.sh
    
    if check_step_status "Istio Control Plane" "kubectl get pods -n istio-system -l app=istiod | grep Running"; then
        echo -e "${GREEN}🎉 Istio gotowy!${NC}"
    else
        echo -e "${RED}❌ Błąd instalacji Istio. Sprawdź logi powyżej.${NC}"
        exit 1
    fi
    
    wait_for_user "Istio gotowy. Naciśnij Enter aby kontynuować z aplikacjami Isotope..."
    
    # Krok 4: Isotope Applications
    show_progress 4 5 "WDROŻENIE APLIKACJI ISOTOPE"
    echo -e "${GREEN}⏱️  Szacowany czas: 10-15 minut${NC}"
    
    ./scripts/04-deploy-isotope.sh
    
    if check_step_status "Isotope Applications" "kubectl get pods -n isotope | grep Running | wc -l | awk '{print (\$1 > 10)}'"; then
        echo -e "${GREEN}🎉 Aplikacje Isotope gotowe!${NC}"
        echo -e "${GREEN}📊 Running pods: $(kubectl get pods -n isotope --no-headers | grep Running | wc -l)${NC}"
    else
        echo -e "${RED}❌ Błąd wdrażania Isotope. Sprawdź logi powyżej.${NC}"
        exit 1
    fi
    
    wait_for_user "Isotope gotowy. Naciśnij Enter aby kontynuować z monitorowaniem..."
    
    # Krok 5: Monitoring Setup
    show_progress 5 5 "KONFIGURACJA MONITOROWANIA"
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
    echo -e "├─ Istio version: $(istioctl version --remote=false 2>/dev/null | head -1 || echo 'Unknown')"
    echo -e "├─ Isotope services: $(kubectl get svc -n isotope --no-headers | wc -l)"
    echo -e "├─ Total pods: $(kubectl get pods --all-namespaces --no-headers | grep Running | wc -l)"
    echo -e "└─ Monitoring: Prometheus + Grafana"
    
    # Pobranie informacji o dostępie
    local grafana_ip=$(kubectl get svc grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "localhost")
    local gateway_ip=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "localhost")
    
    echo -e "\n${BLUE}🌐 DOSTĘP DO ŚRODOWISKA:${NC}"
    if [[ "$grafana_ip" != "localhost" ]]; then
        echo -e "├─ Grafana: http://$grafana_ip:3000 (admin/admin123)"
    else
        echo -e "├─ Grafana: kubectl port-forward -n monitoring svc/grafana 3000:3000"
    fi
    echo -e "├─ Prometheus: kubectl port-forward -n monitoring svc/prometheus 9090:9090"
    if [[ "$gateway_ip" != "localhost" ]]; then
        echo -e "├─ Isotope App: http://$gateway_ip/"
    else
        echo -e "├─ Isotope App: kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80"
    fi
    echo -e "└─ kubectl port-forward -n kwok-system svc/kwok-controller-metrics 10247:10247"
    
    echo -e "\n${BLUE}🧪 TESTY WYDAJNOŚCI:${NC}"
    echo -e "├─ Uruchom testy: ./performance-test.sh"
    echo -e "├─ Test obciążenia: ./test-load.sh"
    echo -e "├─ Przewodnik metryk: docs/metrics-guide.md"
    echo -e "└─ Troubleshooting: docs/troubleshooting.md"
    
    echo -e "\n${BLUE}💾 INFORMACJE ZAPISANE W:${NC}"
    echo -e "├─ cluster-info.txt - informacje o klastrze EKS"
    echo -e "├─ kwok-info.txt - informacje o KWOK"
    echo -e "├─ istio-info.txt - informacje o Istio"
    echo -e "├─ isotope-info.txt - informacje o aplikacjach"
    echo -e "└─ monitoring-info.txt - informacje o monitorowaniu"
    
    echo -e "\n${YELLOW}💡 NASTĘPNE KROKI:${NC}"
    echo -e "1. Sprawdź status środowiska: kubectl get pods --all-namespaces"
    echo -e "2. Uruchom testy wydajności: ./performance-test.sh"
    echo -e "3. Otwórz Grafana dashboard dla wizualizacji metryk"
    echo -e "4. Analizuj metryki zgodnie z docs/metrics-guide.md"
    
    echo -e "\n${GREEN}💰 KOSZTY AWS:${NC}"
    echo -e "Szacowane koszty: \$10-20 USD/dzień"
    echo -e "Pamiętaj o usunięciu środowiska po testach: eksctl delete cluster kwok-performance-test --region ${AWS_REGION:-us-west-2}"
    
    echo -e "\n${GREEN}✅ Środowisko gotowe do analizy wydajności Kubernetes Control Plane!${NC}"
}

# Funkcja cleanup w przypadku błędu
cleanup_on_error() {
    echo -e "\n${RED}❌ Wystąpił błąd podczas instalacji${NC}"
    echo -e "${YELLOW}🧹 Opcje cleanup:${NC}"
    echo -e "1. Restart failed step manually"
    echo -e "2. Full cleanup: eksctl delete cluster --name kwok-performance-test --region ${AWS_REGION:-us-west-2}"
    echo -e "3. Check logs and troubleshooting guide: docs/troubleshooting.md"
}

# Setup error handling
trap cleanup_on_error ERR

# Sprawdź parametry uruchomienia
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Użycie: ./setup-all.sh [--skip-confirmations]"
    echo ""
    echo "Opcje:"
    echo "  --skip-confirmations  Uruchom bez pytań (automatycznie)"
    echo "  --help, -h           Pokaż tę pomoc"
    echo ""
    echo "Zmienne środowiskowe:"
    echo "  AWS_REGION           Region AWS (domyślnie: us-west-2)"
    echo "  CLUSTER_NAME         Nazwa klastra (domyślnie: kwok-performance-test)"
    echo "  INSTANCE_TYPE        Typ instancji (domyślnie: m5.large)"
    echo "  FAKE_NODES_COUNT     Liczba fake nodes (domyślnie: 100)"
    exit 0
fi

# Override funkcji ask_continue jeśli skip confirmations
if [[ "$1" == "--skip-confirmations" ]]; then
    ask_continue() {
        echo -e "${YELLOW}$1 (auto-skipped)${NC}"
    }
    wait_for_user() {
        echo -e "${YELLOW}${1:-Auto-continuing...}${NC}"
        sleep 2
    }
fi

# Uruchom główną funkcję
main

echo -e "\n${GREEN}🎉 Setup completed successfully! Happy performance testing! 🎉${NC}" 