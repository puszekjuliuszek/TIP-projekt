# Projekt: Analiza wydajności Kubernetes Control Plane z KWOK i Istio

[//]: # (## Przegląd projektu)

[//]: # ()
[//]: # (Ten projekt demonstruje jak:)

[//]: # (1. Zainstalować symulator KWOK na klastrze EKS)

[//]: # (2. Wygenerować aplikacje service mesh za pomocą Istio isotope)

[//]: # (3. Przeprowadzić analizę wydajności Kubernetes control plane podczas skalowania)

[//]: # ()
[//]: # (## Wymagania wstępne)

[//]: # ()
[//]: # (- Konto AWS z odpowiednimi uprawnieniami)

[//]: # (- AWS CLI skonfigurowane)

[//]: # (- kubectl zainstalowane)

[//]: # (- Helm 3.x)

[//]: # (- Docker &#40;opcjonalnie&#41;)

[//]: # ()
[//]: # (## Struktura projektu)

[//]: # ()
[//]: # (```)

[//]: # (├── README.md                   # Ta instrukcja)

[//]: # (├── scripts/                    # Skrypty instalacyjne i konfiguracyjne)

[//]: # (│   ├── 01-setup-eks.sh        # Instalacja klastra EKS)

[//]: # (│   ├── 02-install-kwok.sh     # Instalacja KWOK)

[//]: # (│   ├── 03-install-istio.sh    # Instalacja Istio)

[//]: # (│   ├── 04-deploy-isotope.sh   # Wdrożenie aplikacji isotope)

[//]: # (│   └── 05-monitoring.sh       # Konfiguracja monitorowania)

[//]: # (├── configs/                    # Pliki konfiguracyjne)

[//]: # (│   ├── cluster-config.yaml    # Konfiguracja klastra EKS)

[//]: # (│   ├── kwok-config.yaml       # Konfiguracja KWOK)

[//]: # (│   ├── istio-config.yaml      # Konfiguracja Istio)

[//]: # (│   └── isotope-topology.yaml  # Topologia aplikacji isotope)

[//]: # (├── monitoring/                 # Konfiguracje monitorowania)

[//]: # (│   ├── prometheus-config.yaml)

[//]: # (│   ├── grafana-dashboards/)

[//]: # (│   └── alerts.yaml)

[//]: # (└── docs/                      # Dodatkowa dokumentacja)

[//]: # (    ├── metrics-guide.md)

[//]: # (    └── troubleshooting.md)

[//]: # (```)

## Instrukcja krok po kroku

### Krok 1: Przygotowanie środowiska AWS

1. Skonfiguruj AWS CLI z odpowiednimi kredytami:
```bash
aws configure
vim ~/.aws/credentials #jesli uzywasz AWS Academy/VocLabs to jeszcze musisz mieć tutaj tez odpowiednie pola :
# aws_access_key_id = ...
# aws_secret_access_key = ...
# aws_session_token= ...
```

### Krok 2A: Skrypt który robi wszystko

```bash
./setup-all.sh
```

### Krok 2B: Alternatywnie - ręczne utworzenie klastra EKS

Jeśli masz ograniczone uprawnienia AWS (np. AWS Academy/VocLabs):

1. **Utwórz klaster ręcznie przez konsolę AWS** - szczegółowa instrukcja: [`docs/manual-eks-setup.md`](docs/manual-eks-setup.md)
2. **Zweryfikuj klaster**:
   ```bash
   ./verify-eks-cluster.sh
   ```
3. **Uruchom instalację pozostałych komponentów**:
   ```bash
   ./setup-remaining.sh
   ```

### Krok 3: Uruchomienie testów wydajności

Szczegółowe testy znajdziesz w katalogu `docs/metrics-guide.md`

## Metryki do analizy

### Control Plane
- **API Server**: Request latency, throughput, error rates
- **etcd**: Request duration, disk operations, network traffic
- **Scheduler**: Scheduling latency, queue depth
- **Controller Manager**: Work queue depth, reconciliation time

### Service Mesh (Istio)
- **Pilot**: Config distribution time, connected proxies
- **Citadel**: Certificate generation time
- **Galley**: Configuration validation time

### Sieć
- **CoreDNS**: Query latency, cache hit ratio
- **CNI**: Pod networking setup time (limited w KWOK)
- **Kube-proxy**: Iptables rule update time

## Oczekiwane wyniki

Po ukończeniu projektu będziesz mieć:
1. Działający klaster EKS z KWOK
2. Service mesh z Istio i aplikacjami isotope
3. Dashboard Grafana z metrykami wydajności
4. Raporty z testów skalowania
5. Analizę bottlenecków control plane

## Wsparcie

W przypadku problemów sprawdź `docs/troubleshooting.md` lub otwórz issue w tym repozytorium.