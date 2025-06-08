# Ręczna instalacja klastra EKS przez konsolę AWS

## Przegląd
Ta instrukcja pomoże utworzyć klaster EKS ręcznie przez konsolę AWS, co jest idealne dla środowisk z ograniczonymi uprawnieniami CLI (AWS Academy/VocLabs).

## Krok 1: Przygotowanie - tworzenie IAM Role

### 1.1 Utwórz IAM Role dla klastra EKS

1. Idź do **AWS Console → IAM → Roles**
2. Kliknij **"Create role"**
3. Wybierz **"AWS Service"** → **"EKS"** → **"EKS - Cluster"**
4. Kliknij **"Next"**
5. Upewnij się, że następujące policy są dołączone:
   - `AmazonEKSClusterPolicy`
6. Nazwa roli: `kwok-performance-eks-cluster-role`
7. Kliknij **"Create role"**

### 1.2 Utwórz IAM Role dla Node Group

1. Ponownie **IAM → Roles → Create role**
2. Wybierz **"AWS Service"** → **"EC2"**
3. Kliknij **"Next"**
4. Dołącz następujące policy:
   - `AmazonEKSWorkerNodePolicy`
   - `AmazonEKS_CNI_Policy`
   - `AmazonEC2ContainerRegistryReadOnly`
5. Nazwa roli: `kwok-performance-eks-nodegroup-role`
6. Kliknij **"Create role"**

## Krok 2: Utworzenie klastra EKS

### 2.1 Tworzenie klastra

1. Idź do **AWS Console → EKS**
2. Kliknij **"Create cluster"**

### 2.2 Konfiguracja klastra

**Cluster configuration:**
- **Name:** `kwok-performance-test`
- **Kubernetes version:** `1.32`
- **Cluster service role:** `kwok-performance-eks-cluster-role` (utworzona w kroku 1.1)

**Cluster endpoint access:**
- **Endpoint access:** `Public and private`
- Zostaw domyślne ustawienia

**Cluster authentication mode:**
- Zostaw domyślne (`EKS API and ConfigMap`)

**Logging:**
- Jeśli dostępne, włącz **API server** i **Controller manager**
- Jeśli brak uprawnień, zostaw wyłączone

### 2.3 Networking

**VPC and subnets:**
- **VPC:** Wybierz domyślne VPC
- **Subnets:** Wybierz wszystkie dostępne subnety (minimum 2 w różnych AZ)

**Security groups:**
- Zostaw puste (będzie utworzone automatycznie)

**Cluster IP address family:**
- IPv4

### 2.4 Finalizacja

1. **Review** wszystkie ustawienia
2. Kliknij **"Create"**
3. ⏱️ **Czas oczekiwania: 10-15 minut**

## Krok 3: Dodanie Node Group

### 3.1 Po utworzeniu klastra

1. W **EKS Console** → wybierz swój klaster `kwok-performance-test`
2. Idź do zakładki **"Compute"**
3. Kliknij **"Add node group"**

### 3.2 Konfiguracja Node Group

**Node group configuration:**
- **Name:** `primary-nodes`
- **Node IAM role:** `kwok-performance-eks-nodegroup-role` (utworzona w kroku 1.2)

**Node group compute configuration:**
- **AMI type:** `Amazon Linux 2 (AL2_x86_64)`
- **Capacity type:** `On-Demand`
- **Instance types:** `t3.medium` (lub `m5.large` jeśli dostępne)
- **Disk size:** `20 GB`

**Node group scaling configuration:**
- **Desired size:** `2`
- **Minimum size:** `1`
- **Maximum size:** `4`

**Node group update configuration:**
- Zostaw domyślne

### 3.3 Networking

**Subnets:**
- Wybierz te same subnety co dla klastra

**Remote access:**
- **Configure SSH access to nodes:** `Don't configure SSH access`

### 3.4 Finalizacja Node Group

1. **Review** ustawienia
2. Kliknij **"Create"**
3. ⏱️ **Czas oczekiwania: 5-10 minut**

## Krok 4: Konfiguracja kubectl

### 4.1 Aktualizacja kubeconfig

Po utworzeniu klastra, uruchom w terminalu:

```bash
# Zaktualizuj kubeconfig dla nowego klastra
aws eks describe-cluster --region us-east-1 --name kwok-performance-test --query cluster.status
aws eks --region us-east-1 update-kubeconfig --name kwok-performance-test
# Sprawdź połączenie
kubectl get nodes
```

### 4.2 Weryfikacja

Powinieneś zobaczyć podobny output:
```
NAME                                         STATUS   ROLES    AGE   VERSION
ip-192-168-X-X.us-west-2.compute.internal   Ready    <none>   1m    v1.27.X
ip-192-168-Y-Y.us-west-2.compute.internal   Ready    <none>   1m    v1.27.X
```

## Krok 5: Weryfikacja klastra

### 5.1 Sprawdzenie statusu

```bash
# Sprawdź podstawowe informacje klastra
kubectl cluster-info

# Sprawdź węzły
kubectl get nodes -o wide

# Sprawdź systemowe komponenty (w tym Metrics Server)
kubectl get pods -n kube-system
```

Powinieneś zobaczyć:
- ✅ 2 węzły w statusie `Ready`
- ✅ Wszystkie system pods w statusie `Running`
- ✅ Metrics Server już zainstalowany

## Podsumowanie

Po wykonaniu kroków 1-5 masz **pełnoprawny klaster EKS** gotowy do użycia:

✅ **Klaster EKS** `kwok-performance-test`  
✅ **Node Group** z 2 węzłami  
✅ **Metrics Server** (domyślnie w EKS)  
✅ **kubectl** skonfigurowane  

## Następne kroki

**Klaster EKS jest gotowy!** Możesz teraz wrócić do głównego README.md i uruchomić nasze skrypty automatyzacji.

## Szacowane koszty

- **EKS Control Plane:** $0.10/godz = $2.40/dzień
- **2x t3.medium:** $0.0416/godz × 2 = $2.00/dzień  
- **Storage:** ~$0.50/dzień
- **Razem:** ~$5/dzień testowania

## Troubleshooting

**Problem:** Brak uprawnień do tworzenia ról IAM  
**Rozwiązanie:** Poproś instruktora o utworzenie ról lub użyj istniejących

**Problem:** Node Group nie może się utworzyć  
**Rozwiązanie:** Sprawdź czy wybrane subnety mają dostęp do internetu

**Problem:** kubectl nie łączy się z klastrem  
**Rozwiązanie:** 
```bash
aws eks update-kubeconfig --region us-west-2 --name kwok-performance-test --profile your-profile
```

Ta instrukcja powinna działać nawet z ograniczonymi uprawnieniami AWS Academy! 🚀 