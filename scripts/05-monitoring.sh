#!/bin/bash

set -e

# Kolory dla outputu
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Konfiguracja
MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-admin123}"
ISOTOPE_NAMESPACE="${ISOTOPE_NAMESPACE:-isotope}"

echo -e "${GREEN}🚀 Rozpoczynam konfigurację zaawansowanego monitorowania...${NC}"

# Sprawdź czy klaster jest dostępny
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}❌ Błąd: Brak połączenia z klastrem Kubernetes${NC}"
    exit 1
fi

# Oznaczanie nodów
echo -e "${GREEN}🏷️ Oznaczam nody jako simulation=fake|real dla KWOK...${NC}"
for node in $(kubectl get nodes -o name | sed 's|node/||'); do
  if [[ "$node" == *kwok* ]]; then
    kubectl label node "$node" simulation=fake --overwrite
  else
    kubectl label node "$node" simulation=real --overwrite
  fi
done

# Tworzenie namespace dla monitorowania
echo -e "${GREEN}📦 Tworzę namespace dla monitorowania...${NC}"
kubectl create namespace ${MONITORING_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Konfiguracja rozszerzonego Prometheus
# echo -e "${GREEN}📊 Konfiguruję rozszerzony Prometheus dla metryk control plane...${NC}"
# cat > monitoring/prometheus-config.yaml << EOF
# apiVersion: v1
# kind: ConfigMap
# metadata:
#   name: prometheus-config
#   namespace: ${MONITORING_NAMESPACE}
# data:
#   prometheus.yml: |
#     global:
#       scrape_interval: 15s
#       evaluation_interval: 15s
#       external_labels:
#         cluster: 'kwok-performance-test'
#         region: 'aws-eks'
    
#     rule_files:
#     - "/etc/prometheus/rules/*.yml"
    
#     alerting:
#       alertmanagers:
#       - static_configs:
#         - targets:
#           - alertmanager:9093
    
#     scrape_configs:
#     # Kubernetes API Server
#     - job_name: 'kubernetes-apiservers'
#       kubernetes_sd_configs:
#       - role: endpoints
#       relabel_configs:
#       - action: labelmap
#         regex: __meta_kubernetes_node_label_(.+)
#       scheme: https
#       tls_config:
#         ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
#         insecure_skip_verify: true
#       bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
#       relabel_configs:
#       - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
#         action: keep
#         regex: default;kubernetes;https
#       metric_relabel_configs:
#       - source_labels: [__name__]
#         regex: 'apiserver_request_duration_seconds.*|apiserver_request_total|apiserver_current_inflight_requests|etcd_request_duration_seconds.*|etcd_object_counts|process_cpu_seconds_total|process_resident_memory_bytes'
#         action: keep

#     # Kubelet metrics
#     - job_name: 'kubernetes-nodes'
#       kubernetes_sd_configs:
#       - role: node
#       relabel_configs:
#       - action: labelmap
#         regex: __meta_kubernetes_node_label_(.+)
#       scheme: https
#       tls_config:
#         ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
#         insecure_skip_verify: true
#       bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
#       relabel_configs:
#       - action: labelmap
#         regex: __meta_kubernetes_node_label_(.+)
#       - target_label: __address__
#         replacement: kubernetes.default.svc:443
#       - source_labels: [__meta_kubernetes_node_name]
#         regex: (.+)
#         target_label: __metrics_path__
#         replacement: /api/v1/nodes/\${1}/proxy/metrics

#     # Kubelet cAdvisor metrics
#     - job_name: 'kubernetes-cadvisor'
#       kubernetes_sd_configs:
#       - role: node
#       relabel_configs:
#       - action: labelmap
#         regex: __meta_kubernetes_node_label_(.+)
#       scheme: https
#       tls_config:
#         ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
#         insecure_skip_verify: true
#       bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
#       relabel_configs:
#       - action: labelmap
#         regex: __meta_kubernetes_node_label_(.+)
#       - target_label: __address__
#         replacement: kubernetes.default.svc:443
#       - source_labels: [__meta_kubernetes_node_name]
#         regex: (.+)
#         target_label: __metrics_path__
#         replacement: /api/v1/nodes/\${1}/proxy/metrics/cadvisor
#       metric_relabel_configs:
#       - source_labels: [__name__]
#         regex: 'container_cpu_usage_seconds_total|container_memory_usage_bytes|container_network_receive_bytes_total|container_network_transmit_bytes_total'
#         action: keep

#     # Kubernetes service discovery pentru endpoints
#     - job_name: 'kubernetes-service-endpoints'
#       kubernetes_sd_configs:
#       - role: endpoints
#       relabel_configs:
#       - action: labelmap
#         regex: __meta_kubernetes_node_label_(.+)
#       - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scrape]
#         action: keep
#         regex: true
#       - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scheme]
#         action: replace
#         target_label: __scheme__
#         regex: (https?)
#       - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_path]
#         action: replace
#         target_label: __metrics_path__
#         regex: (.+)
#       - source_labels: [__address__, __meta_kubernetes_service_annotation_prometheus_io_port]
#         action: replace
#         target_label: __address__
#         regex: ([^:]+)(?::\d+)?;(\d+)
#         replacement: \$1:\$2
#       - action: labelmap
#         regex: __meta_kubernetes_service_label_(.+)
#       - source_labels: [__meta_kubernetes_namespace]
#         action: replace
#         target_label: kubernetes_namespace
#       - source_labels: [__meta_kubernetes_service_name]
#         action: replace
#         target_label: kubernetes_name

#     # Istio control plane metrics
#     - job_name: 'istiod'
#       kubernetes_sd_configs:
#       - role: endpoints
#         namespaces:
#           names:
#           - istio-system
#       relabel_configs:
#       - action: labelmap
#         regex: __meta_kubernetes_node_label_(.+)
#       - source_labels: [__meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
#         action: keep
#         regex: istiod;http-monitoring
#       - source_labels: [__address__, __meta_kubernetes_endpoint_port_number]
#         action: replace
#         regex: ([^:]+)(?::\d+)?;(\d+)
#         replacement: \$1:\$2
#         target_label: __address__
#       - action: labelmap
#         regex: __meta_kubernetes_service_label_(.+)
#       - source_labels: [__meta_kubernetes_namespace]
#         action: replace
#         target_label: namespace
#       - source_labels: [__meta_kubernetes_service_name]
#         action: replace
#         target_label: service

#     # KWOK controller metrics
#     - job_name: 'kwok-controller'
#       kubernetes_sd_configs:
#       - role: endpoints
#         namespaces:
#           names:
#           - kube-system
#       relabel_configs:
#       - action: labelmap
#         regex: __meta_kubernetes_node_label_(.+)
#       - source_labels: [__meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
#         action: keep
#         regex: kwok-controller-metrics-service;metrics

#     # CoreDNS metrics
#     - job_name: 'coredns'
#       kubernetes_sd_configs:
#       - role: endpoints
#         namespaces:
#           names:
#           - kube-system
#       relabel_configs:
#       - action: labelmap
#         regex: __meta_kubernetes_node_label_(.+)
#       - source_labels: [__meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
#         action: keep
#         regex: kube-dns;metrics

#     # kube-state-metrics
#     - job_name: 'kube-state-metrics'
#       static_configs:
#       - targets:
#         - kube-state-metrics:8080
#         - kube-state-metrics:8081

#     # Node exporter
#     - job_name: 'node-exporter'
#       kubernetes_sd_configs:
#       - role: endpoints
#         namespaces:
#           names:
#           - ${MONITORING_NAMESPACE}
#       relabel_configs:
#       - action: labelmap
#         regex: __meta_kubernetes_node_label_(.+)
#       - source_labels: [__meta_kubernetes_service_name]
#         action: keep
#         regex: node-exporter
#       - source_labels: [__address__, __meta_kubernetes_endpoint_port_number]
#         action: replace
#         regex: ([^:]+)(?::\d+)?;(\d+)
#         replacement: \$1:\$2
#         target_label: __address__

#     # Isotope aplikacje
#     # - job_name: 'isotope-services'
#     #   kubernetes_sd_configs:
#     #   - role: endpoints
#     #     namespaces:
#     #       names:
#     #       - ${ISOTOPE_NAMESPACE}
#     #   relabel_configs:
#     #   - source_labels: [__meta_kubernetes_service_name]
#     #     action: keep
#     #     regex: (frontend|gateway|auth|productcatalog|cart|payment|database|cache|recommendation)
#     #   - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
#     #     action: keep
#     #     regex: true
#     #   - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
#     #     action: replace
#     #     target_label: __metrics_path__
#     #     regex: (.+)
#     #   - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
#     #     action: replace
#     #     regex: ([^:]+)(?::\d+)?;(\d+)
#     #     replacement: \$1:\$2
#     #     target_label: __address__
#     #   - action: labelmap
#     #     regex: __meta_kubernetes_service_label_(.+)
#     #   - source_labels: [__meta_kubernetes_namespace]
#     #     action: replace
#     #     target_label: namespace
#     #   - source_labels: [__meta_kubernetes_service_name]
#     #     action: replace
#     #     target_label: service

#   # Alerting rules dla control plane
#   alerts.yml: |
#     groups:
#     - name: kubernetes-control-plane
#       rules:
#       - alert: KubernetesApiServerDown
#         expr: up{job="kubernetes-apiservers"} == 0
#         for: 5m
#         labels:
#           severity: critical
#         annotations:
#           summary: "Kubernetes API server is down"
#           description: "Kubernetes API server has been down for more than 5 minutes."

#       - alert: KubernetesApiServerHighLatency
#         expr: histogram_quantile(0.99, rate(apiserver_request_duration_seconds_bucket{verb!="WATCH"}[5m])) > 1
#         for: 10m
#         labels:
#           severity: warning
#         annotations:
#           summary: "Kubernetes API server high latency"
#           description: "Kubernetes API server 99th percentile latency is {{ \$value }} seconds"

#       - alert: EtcdHighLatency
#         expr: histogram_quantile(0.99, rate(etcd_request_duration_seconds_bucket[5m])) > 0.5
#         for: 10m
#         labels:
#           severity: warning
#         annotations:
#           summary: "etcd high latency"
#           description: "etcd 99th percentile latency is {{ \$value }} seconds"

#       - alert: KubeControllerManagerDown
#         expr: up{job="kube-controller-manager"} == 0
#         for: 5m
#         labels:
#           severity: critical
#         annotations:
#           summary: "Kube Controller Manager is down"

#       - alert: KubeSchedulerDown
#         expr: up{job="kube-scheduler"} == 0
#         for: 5m
#         labels:
#           severity: critical
#         annotations:
#           summary: "Kube Scheduler is down"

#       - alert: CoreDNSDown
#         expr: up{job="coredns"} == 0
#         for: 5m
#         labels:
#           severity: critical
#         annotations:
#           summary: "CoreDNS is down"

#     - name: istio-control-plane
#       rules:
#       - alert: IstioPilotDown
#         expr: up{job="istiod"} == 0
#         for: 5m
#         labels:
#           severity: critical
#         annotations:
#           summary: "Istio Pilot is down"

#       - alert: IstioPilotHighPushTime
#         expr: histogram_quantile(0.99, rate(pilot_xds_push_time_bucket[5m])) > 10
#         for: 10m
#         labels:
#           severity: warning
#         annotations:
#           summary: "Istio Pilot high push time"
#           description: "Istio Pilot 99th percentile push time is {{ \$value }} seconds"
# ---
# apiVersion: apps/v1
# kind: Deployment
# metadata:
#   name: prometheus
#   namespace: ${MONITORING_NAMESPACE}
#   labels:
#     app: prometheus
# spec:
#   replicas: 1
#   selector:
#     matchLabels:
#       app: prometheus
#   template:
#     metadata:
#       labels:
#         app: prometheus
#     spec:
#       serviceAccountName: prometheus
#       containers:
#       - name: prometheus
#         image: prom/prometheus:v2.45.0
#         args:
#         - '--config.file=/etc/prometheus/prometheus.yml'
#         - '--storage.tsdb.path=/prometheus'
#         - '--web.console.libraries=/etc/prometheus/console_libraries'
#         - '--web.console.templates=/etc/prometheus/consoles'
#         - '--storage.tsdb.retention.time=24h'
#         - '--web.enable-lifecycle'
#         - '--web.enable-admin-api'
#         - '--storage.tsdb.max-block-duration=2h'
#         - '--storage.tsdb.min-block-duration=2h'
#         - '--web.enable-remote-write-receiver'
#         ports:
#         - containerPort: 9090
#           name: web
#         resources:
#           requests:
#             cpu: 100m
#             memory: 512Mi
#           limits:
#             cpu: 500m
#             memory: 1Gi
#         volumeMounts:
#         - name: config
#           mountPath: /etc/prometheus
#         - name: storage
#           mountPath: /prometheus
#         - name: rules
#           mountPath: /etc/prometheus/rules
#       volumes:
#       - name: config
#         configMap:
#           name: prometheus-config
#       - name: storage
#         emptyDir:
#           sizeLimit: 5Gi
#       - name: rules
#         configMap:
#           name: prometheus-config
#           items:
#           - key: alerts.yml
#             path: alerts.yml
# ---
# apiVersion: v1
# kind: Service
# metadata:
#   name: prometheus
#   namespace: ${MONITORING_NAMESPACE}
#   labels:
#     app: prometheus
#   annotations:
#     prometheus.io/scrape: "true"
#     prometheus.io/port: "9090"
# spec:
#   selector:
#     app: prometheus
#   type: LoadBalancer
#   ports:
#   - port: 9090
#     targetPort: 9090
#     name: web
# ---
# apiVersion: v1
# kind: ServiceAccount
# metadata:
#   name: prometheus
#   namespace: ${MONITORING_NAMESPACE}
# ---
# apiVersion: rbac.authorization.k8s.io/v1
# kind: ClusterRole
# metadata:
#   name: prometheus
# rules:
# - apiGroups: [""]
#   resources: ["nodes", "nodes/proxy", "nodes/metrics", "services", "endpoints", "pods"]
#   verbs: ["get", "list", "watch"]
# - apiGroups: ["extensions", "apps"]
#   resources: ["deployments", "replicasets"]
#   verbs: ["get", "list", "watch"]
# - nonResourceURLs: ["/metrics", "/metrics/cadvisor"]
#   verbs: ["get"]
# ---
# apiVersion: rbac.authorization.k8s.io/v1
# kind: ClusterRoleBinding
# metadata:
#   name: prometheus
# roleRef:
#   apiGroup: rbac.authorization.k8s.io
#   kind: ClusterRole
#   name: prometheus
# subjects:
# - kind: ServiceAccount
#   name: prometheus
#   namespace: ${MONITORING_NAMESPACE}
# EOF

kubectl apply -f monitoring/prometheus-config.yaml

# Instalacja kube-state-metrics
echo -e "${GREEN}📊 Instaluję kube-state-metrics...${NC}"
kubectl apply -f configs/kube-state-metrics.yaml

# Pobranie dashboardów Grafany
echo -e "${GREEN}📥 Pobieram dashboardy Grafany...${NC}"
mkdir -p monitoring/dashboards
curl -s https://grafana.com/api/dashboards/7639/revisions/latest/download -o monitoring/dashboards/istio-control-plane.json
curl -s https://grafana.com/api/dashboards/15757/revisions/latest/download -o monitoring/dashboards/kubernetes-control-plane.json

# Utworzenie ConfigMap dla dashboardów
kubectl create configmap grafana-dashboards --from-file=monitoring/dashboards -n ${MONITORING_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Usunięcie starej wersji Grafany, aby uniknąć konfliktów
kubectl delete deployment grafana -n ${MONITORING_NAMESPACE} --ignore-not-found=true

# Konfiguracja Grafany
cat > monitoring/grafana.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-config
  namespace: ${MONITORING_NAMESPACE}
data:
  grafana.ini: |-
    [auth.anonymous]
    enabled = true
    org_role = Viewer
  datasources.yaml: |-
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus.${MONITORING_NAMESPACE}.svc.cluster.local:9090
      access: proxy
      isDefault: true
      uid: prometheus-main
  kwok-dashboards.yaml: |-
    apiVersion: 1
    providers:
    - name: 'kwok-dashboards'
      orgId: 1
      folder: ''
      type: file
      disableDeletion: false
      editable: true
      options:
        path: /var/lib/grafana/dashboards
  dashboards.yaml: |-
    apiVersion: 1
    providers:
    - name: 'default'
      orgId: 1
      folder: ''
      type: file
      disableDeletion: false
      editable: true
      options:
        path: /etc/grafana/provisioning/dashboards/default
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: ${MONITORING_NAMESPACE}
  labels:
    app: grafana
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      securityContext:
        fsGroup: 472
        runAsUser: 472
      containers:
      - name: grafana
        image: grafana/grafana:10.0.0
        ports:
        - containerPort: 3000
          name: http-grafana
          protocol: TCP
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 300m
            memory: 512Mi
        volumeMounts:
        - mountPath: /var/lib/grafana
          name: grafana-storage
        - mountPath: /etc/grafana/grafana.ini
          name: grafana-config
          subPath: grafana.ini
        - mountPath: /etc/grafana/provisioning/datasources/datasources.yaml
          name: grafana-config
          subPath: datasources.yaml
        - mountPath: /etc/grafana/provisioning/dashboards/dashboards.yaml
          name: grafana-config
          subPath: dashboards.yaml
        - name: grafana-dashboards
          mountPath: /etc/grafana/provisioning/dashboards/default
        env:
        - name: GF_SECURITY_ADMIN_PASSWORD
          value: ${GRAFANA_PASSWORD}
        - name: GF_USERS_ALLOW_SIGN_UP
          value: "false"
      volumes:
      - name: grafana-storage
        emptyDir: {}
      - name: grafana-config
        configMap:
          name: grafana-config
      - name: grafana-dashboards
        configMap:
          name: grafana-dashboards
---
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: ${MONITORING_NAMESPACE}
  labels:
    app: grafana
spec:
  selector:
    app: grafana
  type: LoadBalancer
  ports:
  - port: 3000
    targetPort: 3000
    name: http
EOF

kubectl apply -f monitoring/grafana.yaml

# Oczekiwanie na uruchomienie komponentów monitorowania
echo -e "${GREEN}⏳ Oczekuję na uruchomienie komponentów monitorowania...${NC}"
kubectl wait --for=condition=available deployment/prometheus -n ${MONITORING_NAMESPACE} --timeout=300s
kubectl wait --for=condition=available deployment/kube-state-metrics -n ${MONITORING_NAMESPACE} --timeout=300s
kubectl wait --for=condition=available deployment/grafana -n ${MONITORING_NAMESPACE} --timeout=300s

# Sprawdzenie statusu
echo -e "${GREEN}✅ Sprawdzam status komponentów monitorowania...${NC}"
kubectl get pods -n ${MONITORING_NAMESPACE}

# Tworzenie skryptu do testów wydajności
cat > performance-test.sh << 'EOF'
#!/bin/bash

echo "🚀 Rozpoczynam testy wydajności Kubernetes Control Plane..."

# Pobierz adres LoadBalancer Grafana
GRAFANA_IP=$(kubectl get svc grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
if [ -z "$GRAFANA_IP" ]; then
    echo "⚠️  Grafana LoadBalancer nie jest gotowy, używam port-forward..."
    kubectl port-forward -n monitoring svc/grafana 3000:3000 &
    GRAFANA_PID=$!
    GRAFANA_URL="http://localhost:3000"
else
    GRAFANA_URL="http://$GRAFANA_IP:3000"
fi

echo "📊 Grafana dostępna pod: $GRAFANA_URL (admin/admin123)"

# Port-forward dla Prometheus
PROMETHEUS_IP=$(kubectl get svc prometheus -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
if [ -z "$PROMETHEUS_IP" ]; then
    echo "⚠️  Prometheus LoadBalancer nie jest gotowy, używam port-forward..."
    kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
    PROMETHEUS_PID=$!
    PROMETHEUS_URL="http://localhost:9090"
else
    PROMETHEUS_URL="http://$PROMETHEUS_IP:9090"
fi

echo "📈 Prometheus dostępny pod: $PROMETHEUS_URL"

# Test skalowania dla sprawdzenia wydajności
echo "🔧 Rozpoczynam test skalowania aplikacji isotope..."

# Konfiguracja
ISOTOPE_NAMESPACE="${ISOTOPE_NAMESPACE:-testapp}"
GRAFANA_URL="$GRAFANA_URL"
PROMETHEUS_URL="$PROMETHEUS_URL"

cleanup() {
    echo "🧹 Czyszczenie po teście..."
    # Przywracanie pierwotnej liczby replik
    scale_app frontend 1
    scale_app gateway 1
    scale_app auth 1
    scale_app productcatalog 1
    scale_app cart 1
    scale_app payment 1
    scale_app database 1
    scale_app cache 1
    kill $PROMETHEUS_PID
    kill $GRAFANA_PID
}

trap cleanup EXIT

scale_app() {
    echo "📈 Skaluję $1 do $2 replik..."
    kubectl scale deployment/$1 --replicas=$2 -n ${ISOTOPE_NAMESPACE} || echo "⚠️  Nie udało się przeskalować $1"
}

# Skalowanie w górę
APPS="frontend gateway auth productcatalog cart payment database cache"
for app in $APPS; do
    scale_app $app 10
    sleep 5 # Krótka pauza między skalowaniem
done

# Czekaj na ustabilizowanie się metryk
echo "⏳ Czekam 60 sekund na ustabilizowanie się metryk..."
sleep 60

echo "📊 Sprawdzam kluczowe metryki wydajności:"

echo "1. API Server Request Latency (99th percentile):"
curl -s "$PROMETHEUS_URL/api/v1/query?query=histogram_quantile(0.99,%20rate(apiserver_request_duration_seconds_bucket{verb!=\"WATCH\"}[5m]))" | jq -r '.data.result[0].value[1] // "N/A"' | xargs -I {} echo "   {} seconds"

echo "2. etcd Request Latency (99th percentile):"
curl -s "$PROMETHEUS_URL/api/v1/query?query=histogram_quantile(0.99,%20rate(etcd_request_duration_seconds_bucket[5m]))" | jq -r '.data.result[0].value[1] // "N/A"' | xargs -I {} echo "   {} seconds"

echo "3. Scheduler Queue Depth:"
curl -s "$PROMETHEUS_URL/api/v1/query?query=scheduler_pending_pods" | jq -r '.data.result[0].value[1] // "N/A"' | xargs -I {} echo "   {} pods"

echo "4. Current Running Pods:"
kubectl get pods --all-namespaces --no-headers | grep Running | wc -l | xargs -I {} echo "   {} pods"

echo "5. Current KWOK Nodes:"
kubectl get nodes --selector=type=kwok --no-headers | wc -l | xargs -I {} echo "   {} nodes"

echo "6. Istio Pilot Push Time (99th percentile):"
curl -s "$PROMETHEUS_URL/api/v1/query?query=histogram_quantile(0.99,%20rate(pilot_xds_push_time_bucket[5m]))" | jq -r '.data.result[0].value[1] // "N/A"' | xargs -I {} echo "   {} seconds"

# Skalowanie w dół
echo "📉 Skaluję z powrotem do początkowej liczby replik..."
for app in $APPS; do
    scale_app $app 1
done

echo "✅ Test wydajności zakończony!"
echo "📊 Sprawdź dashboardy Grafana: $GRAFANA_URL"
echo "📈 Sprawdź metryki Prometheus: $PROMETHEUS_URL"
EOF

chmod +x performance-test.sh

# Zapisanie informacji o monitorowaniu
PROMETHEUS_LB=$(kubectl get svc prometheus -n ${MONITORING_NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Pending...")
GRAFANA_LB=$(kubectl get svc grafana -n ${MONITORING_NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Pending...")

cat > monitoring-info.txt << EOF
Advanced Monitoring Setup
=========================
Namespace: ${MONITORING_NAMESPACE}

Komponenty:
- Prometheus: Zbieranie metryk
- Grafana: Wizualizacja (hasło: ${GRAFANA_PASSWORD})
- kube-state-metrics: Metryki stanu klastra

Dostęp:
- Grafana: http://$GRAFANA_LB:3000 (admin/${GRAFANA_PASSWORD})
- Prometheus: http://$PROMETHEUS_LB:9090

Kluczowe metryki monitorowane:
- API Server latency i throughput
- etcd performance
- Scheduler queue depth
- Controller Manager metrics
- CoreDNS performance
- Istio control plane metrics
- KWOK controller metrics

Dashboardy Grafana:
- Kubernetes Control Plane Performance
- Istio Control Plane Performance

Testy wydajności:
- ./performance-test.sh

Port-forwards dla dostępu lokalnego:
- kubectl port-forward -n ${MONITORING_NAMESPACE} svc/grafana 3000:3000
- kubectl port-forward -n ${MONITORING_NAMESPACE} svc/prometheus 9090:9090

Sprawdzanie statusu:
- kubectl get pods -n ${MONITORING_NAMESPACE}
- kubectl logs -n ${MONITORING_NAMESPACE} deployment/prometheus
- kubectl logs -n ${MONITORING_NAMESPACE} deployment/grafana

Konfigurowano: $(date)
EOF

# ✅ DODANE: Wskazówki do Grafany
echo -e "${YELLOW}📈 Możesz teraz użyć następujących zapytań w Grafanie:${NC}"
echo -e "${YELLOW}▶ Rozkład podów na nodach: count by(node) (kube_pod_info)${NC}"
echo -e "${YELLOW}▶ CPU per simulation type: sum by(node_label_simulation) (rate(container_cpu_usage_seconds_total[5m]))${NC}"
echo -e "${YELLOW}▶ Ruch Istio po typie noda: sum by(node_label_simulation) (rate(istio_requests_total[5m]))${NC}"

echo -e "${GREEN}🎉 Zaawansowane monitorowanie zostało skonfigurowane!${NC}"
echo -e "${GREEN}📊 Status:${NC}"
echo -e "   • Prometheus: $(kubectl get pods -n ${MONITORING_NAMESPACE} -l app=prometheus --no-headers | grep Running | wc -l)/1 running"
echo -e "   • Grafana: $(kubectl get pods -n ${MONITORING_NAMESPACE} -l app=grafana --no-headers | grep Running | wc -l)/1 running"
echo -e "   • kube-state-metrics: $(kubectl get pods -n ${MONITORING_NAMESPACE} -l app=kube-state-metrics --no-headers | grep Running | wc -l)/1 running"
echo -e "${GREEN}🌐 Dostęp:${NC}"
echo -e "   • Grafana: http://$GRAFANA_LB:3000 (admin/${GRAFANA_PASSWORD})"
echo -e "   • Prometheus: http://$PROMETHEUS_LB:9090"
echo -e "${GREEN}📁 Informacje zapisane w monitoring-info.txt${NC}"
echo -e "${GREEN}🧪 Zrób trochę ruchu w apce jak jeszcze nie zrobiłes: ./test-load.sh${NC}"
echo -e "${GREEN}🧪 Uruchom testy wydajności: ./performance-test.sh${NC}"
echo -e "${GREEN}✅ Projekt gotowy do analizy wydajności!${NC}"
