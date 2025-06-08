# Przewodnik troubleshootingu

Ten dokument zawiera rozwiązania typowych problemów, które mogą wystąpić podczas instalacji i użytkowania środowiska KWOK + Istio + EKS.

## Problemy z instalacją EKS

### Problem: Błąd "insufficient capacity" podczas tworzenia node group

**Objawy:**
```
error creating EKS Node Group: InvalidParameterException: Insufficient capacity
```

**Rozwiązanie:**
1. Zmień typ instancji w konfiguracji:
```bash
export INSTANCE_TYPE=m5.medium  # lub t3.medium
./scripts/01-setup-eks.sh
```

2. Lub zmień region:
```bash
export AWS_REGION=us-east-1
./scripts/01-setup-eks.sh
```

3. Sprawdź dostępność instancji w różnych AZ:
```bash
aws ec2 describe-instance-type-offerings --location-type availability-zone --filters Name=instance-type,Values=m5.large --region us-west-2
```

### Problem: AWS CLI nie jest skonfigurowane

**Objawy:**
```
error: You must be logged in to the server (Unauthorized)
```

**Rozwiązanie:**
```bash
# Sprawdź konfigurację AWS
aws sts get-caller-identity

# Jeśli błąd, skonfiguruj AWS CLI
aws configure
# Wprowadź: Access Key ID, Secret Access Key, Region, Output format (json)

# Lub użyj AWS SSO/Profile
aws configure --profile your-profile
export AWS_PROFILE=your-profile
```

### Problem: Brak uprawnień do tworzenia zasobów EKS

**Objawy:**
```
User: arn:aws:iam::123456789012:user/username is not authorized to perform: eks:CreateCluster
```

**Rozwiązanie:**
Dodaj następujące uprawnienia do użytkownika/roli IAM:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "eks:*",
                "ec2:*",
                "iam:CreateServiceLinkedRole",
                "iam:PassRole"
            ],
            "Resource": "*"
        }
    ]
}
```

## Problemy z KWOK

### Problem: KWOK controller nie startuje

**Objawy:**
```bash
kubectl get pods -n kwok-system
# KWOK pod w stanie CrashLoopBackOff
```

**Diagnoza:**
```bash
kubectl logs -n kwok-system deployment/kwok-controller
kubectl describe pod -n kwok-system -l app=kwok-controller
```

**Typowe przyczyny i rozwiązania:**

1. **Błąd RBAC permissions:**
```bash
# Sprawdź RBAC
kubectl auth can-i create nodes --as=system:serviceaccount:kwok-system:kwok-controller

# Jeśli "no", zastosuj ponownie RBAC:
kubectl apply -f configs/kwok-config.yaml
```

2. **Nieprawidłowa konfiguracja:**
```bash
# Sprawdź ConfigMap
kubectl get configmap kwok-config -n kwok-system -o yaml

# Restart controllera
kubectl rollout restart deployment/kwok-controller -n kwok-system
```

### Problem: Fake nodes nie są tworzone

**Objawy:**
```bash
kubectl get nodes --selector=type=kwok
# Brak wyników lub nodes w stanie NotReady
```

**Rozwiązanie:**
1. Sprawdź Stage configuration:
```bash
kubectl get stages
kubectl describe stage node-initialize
```

2. Sprawdź logi KWOK controller:
```bash
kubectl logs -n kwok-system deployment/kwok-controller | grep -i error
```

3. Manualne utworzenie testowego node:
```bash
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Node
metadata:
  name: test-kwok-node
  labels:
    type: kwok
spec:
  taints:
  - effect: NoSchedule
    key: kwok.x-k8s.io/node
    value: fake
status:
  allocatable:
    cpu: "2"
    memory: 4Gi
    pods: "110"
  capacity:
    cpu: "2"
    memory: 4Gi
    pods: "110"
  phase: Running
EOF
```

### Problem: Pods nie są schedulowane na fake nodes

**Objawy:**
Pods pozostają w stanie `Pending` z powodu:
```
0/103 nodes are available: 103 node(s) had taint {kwok.x-k8s.io/node: fake}
```

**Rozwiązanie:**
Dodaj tolerations do podów:
```yaml
spec:
  tolerations:
  - key: kwok.x-k8s.io/node
    operator: Exists
    effect: NoSchedule
  nodeSelector:
    type: kwok
```

## Problemy z Istio

### Problem: Istio installation fails

**Objawy:**
```
error: the server could not find the requested resource (post istioperators.install.istio.io)
```

**Rozwiązanie:**
1. Sprawdź czy istioctl jest zainstalowane:
```bash
istioctl version

# Jeśli nie, zainstaluj:
curl -L https://istio.io/downloadIstio | sh -
sudo mv istio-*/bin/istioctl /usr/local/bin/
```

2. Zainstaluj Istio operator:
```bash
istioctl operator init
kubectl wait --for=condition=available deployment/istio-operator -n istio-operator --timeout=300s
```

### Problem: Sidecar injection nie działa

**Objawy:**
Pods nie mają sidecar proxy (tylko 1 container zamiast 2).

**Rozwiązanie:**
1. Sprawdź labeling namespace:
```bash
kubectl get namespace isotope -o yaml | grep istio-injection
```

2. Jeśli brak labela:
```bash
kubectl label namespace isotope istio-injection=enabled
```

3. Restart deployments:
```bash
kubectl rollout restart deployment -n isotope
```

4. Sprawdź webhook configuration:
```bash
kubectl get mutatingwebhookconfiguration istio-sidecar-injector -o yaml
```

### Problem: Istio gateway nie ma external IP

**Objawy:**
```bash
kubectl get svc istio-ingressgateway -n istio-system
# EXTERNAL-IP shows <pending>
```

**Rozwiązanie:**
1. Sprawdź czy AWS Load Balancer Controller jest zainstalowany:
```bash
kubectl get pods -n kube-system | grep aws-load-balancer-controller
```

2. Jeśli nie, zainstaluj:
```bash
# W skrypcie 01-setup-eks.sh jest już uwzględnione
./scripts/01-setup-eks.sh
```

3. Sprawdź service annotations:
```bash
kubectl get svc istio-ingressgateway -n istio-system -o yaml
```

4. Dla środowiska testowego, użyj NodePort:
```bash
kubectl patch svc istio-ingressgateway -n istio-system -p '{"spec":{"type":"NodePort"}}'
```

## Problemy z aplikacjami Isotope

### Problem: Isotope pods nie startują

**Objawy:**
```bash
kubectl get pods -n isotope
# Pods w stanie ImagePullBackOff lub CrashLoopBackOff
```

**Rozwiązanie:**
1. **ImagePullBackOff** - sprawdź dostępność image:
```bash
kubectl describe pod -n isotope <pod-name>

# Jeśli problem z 'latest' tag, użyj konkretną wersję:
# W skrypcie zmień ISOTOPE_VERSION na konkretną wersję np. "1.0.0"
```

2. **CrashLoopBackOff** - sprawdź logi:
```bash
kubectl logs -n isotope <pod-name> -c isotope
```

3. **ConfigMap issues**:
```bash
kubectl get configmap isotope-config -n isotope -o yaml
```

### Problem: Brak ruchu między serwisami

**Objawy:**
Load generator nie generuje ruchu lub metryki nie pokazują komunikacji.

**Rozwiązanie:**
1. Sprawdź connectivity:
```bash
kubectl exec -n isotope deployment/frontend -- curl -v http://gateway:8080/health
```

2. Sprawdź Istio virtual services:
```bash
kubectl get virtualservices -n isotope
istioctl analyze -n isotope
```

3. Sprawdź sidecar proxy status:
```bash
istioctl proxy-status
istioctl proxy-config cluster deployment/frontend.isotope
```

## Problemy z monitorowaniem

### Problem: Prometheus nie zbiera metryk

**Objawy:**
W Prometheus targets pokazują status "down" lub brak danych.

**Rozwiązanie:**
1. Sprawdź targets w Prometheus UI:
```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Otwórz http://localhost:9090/targets
```

2. Sprawdź RBAC dla Prometheus:
```bash
kubectl auth can-i get pods --as=system:serviceaccount:monitoring:prometheus
```

3. Sprawdź network policies:
```bash
kubectl get networkpolicies -A
```

4. Sprawdź service discovery:
```bash
kubectl get endpoints -n istio-system istiod
kubectl get endpoints -n kwok-system kwok-controller-metrics
```

### Problem: Grafana nie może połączyć się z Prometheus

**Objawy:**
Dashboardy w Grafana pokazują "No data" lub błędy połączenia.

**Rozwiązanie:**
1. Sprawdź datasource configuration:
```bash
kubectl logs -n monitoring deployment/grafana | grep -i prometheus
```

2. Test connectivity z Grafana pod:
```bash
kubectl exec -n monitoring deployment/grafana -- curl -v http://prometheus:9090/api/v1/query?query=up
```

3. Sprawdź ConfigMap datasource:
```bash
kubectl get configmap grafana-config -n monitoring -o yaml
```

### Problem: High cardinality metrics

**Objawy:**
Prometheus używa dużo pamięci, slow queries.

**Rozwiązanie:**
1. Sprawdź cardinality:
```bash
# W Prometheus UI:
# http://localhost:9090/api/v1/label/__name__/values
```

2. Dodaj metric_relabel_configs do ograniczenia metryk:
```yaml
metric_relabel_configs:
- source_labels: [__name__]
  regex: '(istio_request_duration_milliseconds|apiserver_request_duration_seconds).*'
  action: keep
```

## Problemy z wydajnością

### Problem: High API Server latency

**Objawy:**
```
histogram_quantile(0.99, rate(apiserver_request_duration_seconds_bucket[5m])) > 1
```

**Diagnoza:**
```bash
# Sprawdź top API consumers
kubectl top nodes
kubectl get pods --all-namespaces --sort-by=.status.containerStatuses[0].restartCount

# Sprawdź API server logs
kubectl logs -n kube-system -l component=kube-apiserver
```

**Rozwiązanie:**
1. Zwiększ resources dla control plane (w managed EKS automatyczne)
2. Ograniczy częstotliwość polling:
```bash
# Zmniejsz scrape interval w Prometheus
# Ograniczy concurrent requests do API
```

### Problem: High etcd latency

**Objawy:**
```
histogram_quantile(0.99, rate(etcd_request_duration_seconds_bucket[5m])) > 0.2
```

**Rozwiązanie:**
1. Sprawdź disk performance:
```bash
# W EKS managed - kontaktuj AWS support
# Check CloudWatch metrics dla EKS control plane
```

2. Ograniczy write load:
```bash
# Zmniejsz frequency updates w KWOK
# Ograniczy annotation/label updates
```

## Problemy z siecią

### Problem: DNS resolution fails

**Objawy:**
```bash
kubectl exec -it test-pod -- nslookup kubernetes.default
# server can't find kubernetes.default: NXDOMAIN
```

**Rozwiązanie:**
1. Sprawdź CoreDNS:
```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns
```

2. Test DNS:
```bash
kubectl apply -f https://k8s.io/examples/admin/dns/dnsutils.yaml
kubectl exec -it dnsutils -- nslookup kubernetes.default
```

3. Sprawdź CoreDNS ConfigMap:
```bash
kubectl get configmap coredns -n kube-system -o yaml
```

### Problem: Service mesh connectivity issues

**Objawy:**
503 errors between services, timeout errors.

**Rozwiązanie:**
1. Sprawdź Envoy proxy configuration:
```bash
istioctl proxy-config cluster deployment/frontend.isotope
istioctl proxy-config listeners deployment/frontend.isotope
```

2. Sprawdź circuit breaker settings:
```bash
kubectl get destinationrule -n isotope -o yaml
```

3. Sprawdź logs sidecar:
```bash
kubectl logs -n isotope deployment/frontend -c istio-proxy
```

## Cleanup i recovery

### Kompletne czyszczenie środowiska

```bash
# Usuń klaster EKS
eksctl delete cluster --name kwok-performance-test --region us-west-2

# Cleanup local files
rm -f cluster-info.txt kwok-info.txt istio-info.txt isotope-info.txt monitoring-info.txt
rm -f test-load.sh performance-test.sh

# Cleanup Docker images (opcjonalnie)
docker system prune -f
```

### Recovery po błędach

```bash
# Restart wszystkich komponentów
kubectl rollout restart deployment -n kwok-system
kubectl rollout restart deployment -n istio-system
kubectl rollout restart deployment -n isotope
kubectl rollout restart deployment -n monitoring

# Sprawdź status
kubectl get pods --all-namespaces | grep -v Running
```

### Backup konfiguracji

```bash
# Backup wszystkich konfiguracji
kubectl get all --all-namespaces -o yaml > full-backup.yaml

# Backup tylko custom resources
kubectl get istiooperators,stages,virtualservices,destinationrules -A -o yaml > istio-kwok-backup.yaml
```

## Przydatne komendy debug

```bash
# Comprehensive cluster status
kubectl get nodes,pods --all-namespaces -o wide

# Check all events
kubectl get events --all-namespaces --sort-by='.metadata.creationTimestamp'

# Resource usage
kubectl top nodes
kubectl top pods --all-namespaces

# Network debugging
kubectl run test-pod --image=busybox -it --rm -- sh
kubectl run curl-pod --image=curlimages/curl -it --rm -- sh

# Istio debugging
istioctl analyze --all-namespaces
istioctl proxy-status
istioctl version

# KWOK debugging
kubectl get stages
kubectl get nodes -l type=kwok
kubectl logs -n kwok-system deployment/kwok-controller
```

## Kontakt w przypadku problemów

1. Sprawdź GitHub Issues dla KWOK: https://github.com/kubernetes-sigs/kwok/issues
2. Istio troubleshooting: https://istio.io/latest/docs/ops/troubleshooting/
3. EKS troubleshooting: https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html

Ten dokument powinien pomóc w rozwiązaniu większości problemów. W przypadku nowych problemów, dodaj je do tego dokumentu z rozwiązaniami. 