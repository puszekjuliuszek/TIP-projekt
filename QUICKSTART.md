# Quick Start Guide

🚀 **Szybki start dla projektu analizy wydajności Kubernetes Control Plane**

## Przed rozpoczęciem

### Wymagania
- Konto AWS z odpowiednimi uprawnieniami
- AWS CLI skonfigurowane
- macOS lub Linux
- Około 1-2 godzin na pełną instalację

### Szacowane koszty
💰 **$10-20 USD/dzień** testowania

## Opcja 1: Automatyczna instalacja (Zalecana)

```bash
# Sklonuj repozytorium (jeśli jeszcze nie masz)
git clone <repository-url>
cd TIP-projekt

# Skonfiguruj AWS (jeśli jeszcze nie)
aws configure

# Uruchom automatyczną instalację
./setup-all.sh
```

**Czas instalacji:** 40-60 minut (większość to czekanie na AWS)

## Opcja 2: Instalacja krok po kroku

```bash
# 1. Utwórz klaster EKS (15-20 min)
./scripts/01-setup-eks.sh

# 2. Zainstaluj KWOK (5-10 min)
./scripts/02-install-kwok.sh

# 3. Zainstaluj Istio (5-10 min)
./scripts/03-install-istio.sh

# 4. Wdróż aplikacje Isotope (10-15 min)
./scripts/04-deploy-isotope.sh

# 5. Skonfiguruj monitorowanie (5-10 min)
./scripts/05-monitoring.sh
```

## Opcja 3: Bez potwierdzeń (CI/CD)

```bash
# Uruchom bez interakcji
./setup-all.sh --skip-confirmations
```

## Opcja 4: Ręczne utworzenie klastra EKS (AWS Academy/VocLabs)

Jeśli masz ograniczone uprawnienia AWS CLI:

```bash
# 1. Utwórz klaster ręcznie przez konsolę AWS
# Szczegółowa instrukcja: docs/manual-eks-setup.md

# 2. Skonfiguruj kubectl
aws eks update-kubeconfig --region us-west-2 --name kwok-performance-test

# 3. Zweryfikuj klaster
./verify-eks-cluster.sh

# 4. Zainstaluj pozostałe komponenty automatycznie
./setup-remaining.sh
```

## Po instalacji

### Sprawdź status
```bash
kubectl get pods --all-namespaces
kubectl get nodes
```

### Dostęp do dashboardów
```bash
# Grafana (admin/admin123)
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# Aplikacja testowa
kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80
```

### Uruchom testy wydajności
```bash
# Test wydajności control plane
./performance-test.sh

# Test obciążenia aplikacji
./test-load.sh
```

## Kluczowe metryki do obserwacji

### W Prometheus (localhost:9090)
```promql
# API Server latency (99th percentile)
histogram_quantile(0.99, rate(apiserver_request_duration_seconds_bucket{verb!="WATCH"}[5m]))

# etcd latency
histogram_quantile(0.99, rate(etcd_request_duration_seconds_bucket[5m]))

# Scheduler latency
histogram_quantile(0.99, rate(scheduler_scheduling_duration_seconds_bucket[5m]))

# Istio Pilot push time
histogram_quantile(0.99, rate(pilot_xds_push_time_bucket[5m]))
```

### W Grafana (localhost:3000)
- Kubernetes Control Plane Performance
- Istio Control Plane Performance
- Custom dashboards w `/monitoring/grafana-dashboards/`

## Typowe problemy i rozwiązania

### Problem: AWS insufficient capacity
```bash
export INSTANCE_TYPE=m5.medium
export AWS_REGION=us-east-1
./scripts/01-setup-eks.sh
```

### Problem: LoadBalancer pending
```bash
# Użyj port-forward zamiast LoadBalancer
kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80
```

### Problem: Pods nie startują na fake nodes
```bash
# Sprawdź tolerations w deploymentach
kubectl get pods -n isotope -o yaml | grep -A5 tolerations
```

## Struktura środowiska po instalacji

```
📊 ŚRODOWISKO:
├─ EKS Cluster (3 real nodes)
├─ KWOK (100 fake nodes)
├─ Istio Service Mesh
├─ Isotope Applications (11 microservices)
└─ Monitoring Stack (Prometheus + Grafana)

🌐 DOSTĘP:
├─ Grafana: http://localhost:3000 (admin/admin123)
├─ Prometheus: http://localhost:9090
├─ KWOK metrics: http://localhost:10247 (po port-forward)
└─ Isotope app: http://localhost:8080 (po port-forward)
```

## Czyszczenie środowiska

```bash
# Usuń cały klaster EKS
eksctl delete cluster --name kwok-performance-test --region us-west-2

# Cleanup lokalne pliki
rm -f *.txt *.sh
```

## Dokumentacja szczegółowa

- 📖 **README.md** - Pełna dokumentacja projektu
- 📊 **docs/metrics-guide.md** - Przewodnik po metrykach
- 🔧 **docs/troubleshooting.md** - Rozwiązywanie problemów

## Wsparcie

W przypadku problemów:
1. Sprawdź **docs/troubleshooting.md**
2. Sprawdź logi: `kubectl logs -n <namespace> <pod-name>`
3. Sprawdź status: `kubectl get pods --all-namespaces`

---

**🎯 Cel projektu:** Analiza wydajności Kubernetes control plane podczas skalowania aplikacji w service mesh z symulowanymi węzłami KWOK.

**📈 Metryki focus:** API Server latency, etcd performance, Scheduler throughput, Istio control plane, CoreDNS performance. 