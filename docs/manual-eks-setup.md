# Ręczna instalacja klastra EKS przez konsolę AWS

## Przegląd
Ta instrukcja pomoże utworzyć klaster EKS ręcznie przez konsolę AWS, co jest idealne dla środowisk z ograniczonymi uprawnieniami CLI (AWS Academy/VocLabs).

## Krok 1: Utworzenie klastra EKS

### 1.1 Tworzenie klastra

1. Idź do **AWS Console → EKS**
2. Kliknij **"Create cluster"**

### 1.2 Konfiguracja klastra

**Cluster configuration:**
- **Custom configuration**
- **Use EKS Auto Mode:** wyłaczyc
- **Name:** `kwok-performance-test`
- **Cluster service role:** `Lab Role`
- **Kubernetes version:** `1.32`

**VPC and subnets:**
- **VPC:** Wybierz domyślne VPC
- **Subnets:** Wybierz subnety 1a i 1b


### 1.3 Finalizacja

1. **Review** wszystkie ustawienia
2. Kliknij **"Create"**
3. ⏱️ **Czas oczekiwania: 10-15 minut**

## Krok 2: Dodanie Node Group

### 2.1 Po utworzeniu klastra

1. W **EKS Console** → wybierz swój klaster `kwok-performance-test`
2. Idź do zakładki **"Compute"**
3. Kliknij **"Add node group"**

### 2.2 Konfiguracja Node Group

**Node group configuration:**
- **Name:** `primary-nodes`
- **Node IAM role:** `Lab Role` 

**Node group compute configuration:**
- **AMI type:** `Amazon Linux 2023`
- **Capacity type:** `On-Demand`
- **Instance types:** `t3.large` 
- **Disk size:** `20 GB`

**Node group scaling configuration:**
- **Desired size:** `2`
- **Minimum size:** `1`
- **Maximum size:** `4`

### 2.3 Networking

**Subnets:**
- Wybierz te same subnety co dla klastra

**Remote access:**
- **Configure SSH access to nodes:** `Don't configure SSH access`

### 2.4 Finalizacja Node Group

1. **Review** ustawienia
2. Kliknij **"Create"**
3. ⏱️ **Czas oczekiwania: 5-10 minut**

## Krok 3: Konfiguracja kubectl

### 3.1 Aktualizacja kubeconfig

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