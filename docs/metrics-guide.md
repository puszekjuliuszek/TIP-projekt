# Przewodnik po metrykach wydajności

Ten dokument opisuje kluczowe metryki do analizy wydajności Kubernetes control plane i Istio service mesh w środowisku z KWOK.

## Metryki Kubernetes Control Plane

### API Server

#### Opóźnienia żądań (Request Latency)
```promql
# 99-ty percentyl opóźnień API Server
histogram_quantile(0.99, rate(apiserver_request_duration_seconds_bucket{verb!="WATCH"}[5m]))

# Breakdown według zasobów
histogram_quantile(0.99, rate(apiserver_request_duration_seconds_bucket{verb!="WATCH"}[5m])) by (resource)

# Opóźnienia tylko dla operacji write
histogram_quantile(0.99, rate(apiserver_request_duration_seconds_bucket{verb=~"POST|PUT|PATCH|DELETE"}[5m]))
```

#### Throughput żądań
```promql
# Ogólny throughput
rate(apiserver_request_total[5m])

# Breakdown według verbs
rate(apiserver_request_total[5m]) by (verb)

# Error rate
rate(apiserver_request_total{code=~"5.."}[5m]) / rate(apiserver_request_total[5m])
```

#### Inflight żądania
```promql
# Aktualna liczba przetwarzanych żądań
apiserver_current_inflight_requests

# Breakdown read/write
apiserver_current_inflight_requests by (requestKind)
```

### etcd

#### Latencja żądań etcd
```promql
# 99-ty percentyl latencji etcd
histogram_quantile(0.99, rate(etcd_request_duration_seconds_bucket[5m]))

# Breakdown według operacji
histogram_quantile(0.99, rate(etcd_request_duration_seconds_bucket[5m])) by (operation)

# Backend commit duration
histogram_quantile(0.99, rate(etcd_disk_backend_commit_duration_seconds_bucket[5m]))
```

#### Operacje dyskowe etcd
```promql
# WAL fsync duration
histogram_quantile(0.99, rate(etcd_disk_wal_fsync_duration_seconds_bucket[5m]))

# Backend commit latency
histogram_quantile(0.99, rate(etcd_disk_backend_commit_duration_seconds_bucket[5m]))
```

#### Rozmiar bazy danych etcd
```promql
# Rozmiar bazy danych
etcd_mvcc_db_total_size_in_bytes

# Liczba kluczy
etcd_debugging_mvcc_keys_total

# Liczba rewizji
etcd_debugging_mvcc_current_revision
```

### Scheduler

#### Latencja schedulowania
```promql
# 99-ty percentyl czasu schedulowania
histogram_quantile(0.99, rate(scheduler_scheduling_duration_seconds_bucket[5m]))

# Breakdown według algorytmu
histogram_quantile(0.99, rate(scheduler_scheduling_duration_seconds_bucket[5m])) by (operation)

# Framework extension latency
histogram_quantile(0.99, rate(scheduler_framework_extension_point_duration_seconds_bucket[5m])) by (extension_point)
```

#### Kolejka schedulera
```promql
# Liczba podów oczekujących
scheduler_pending_pods

# Work queue depth
workqueue_depth{name="default"}

# Work queue processing rate
rate(workqueue_adds_total{name="default"}[5m])
```

### Controller Manager

#### Work queue metryki
```promql
# Depth kolejki dla każdego controllera
workqueue_depth by (name)

# Processing rate
rate(workqueue_adds_total[5m]) by (name)

# Retries
rate(workqueue_retries_total[5m]) by (name)

# Work duration
histogram_quantile(0.99, rate(workqueue_work_duration_seconds_bucket[5m])) by (name)
```

#### Controller-specific metryki
```promql
# Node controller
node_collector_evictions_total

# ReplicaSet controller
replicaset_controller_sorting_deletion_age_ratio

# Deployment controller
deployment_controller_sync_duration_seconds
```

### CoreDNS

#### Latencja DNS
```promql
# Request duration
histogram_quantile(0.99, rate(coredns_dns_request_duration_seconds_bucket[5m]))

# Breakdown według typu
histogram_quantile(0.99, rate(coredns_dns_request_duration_seconds_bucket[5m])) by (type)
```

#### Cache metrics
```promql
# Cache hits/misses
rate(coredns_cache_hits_total[5m])
rate(coredns_cache_misses_total[5m])

# Cache size
coredns_cache_size by (type)
```

#### Error rate
```promql
# DNS request errors
rate(coredns_dns_request_count_total{rcode!="NOERROR"}[5m]) / rate(coredns_dns_request_count_total[5m])
```

## Metryki Istio Control Plane

### Pilot (istiod)

#### XDS Push metryki
```promql
# Push time latency
histogram_quantile(0.99, rate(pilot_xds_push_time_bucket[5m]))

# Push size
histogram_quantile(0.99, rate(pilot_xds_config_size_bytes_bucket[5m]))

# Connected proxies
pilot_xds_pushes

# Proxy convergence time
histogram_quantile(0.99, rate(pilot_proxy_convergence_time_bucket[5m]))
```

#### Configuration processing
```promql
# Config processing time
histogram_quantile(0.99, rate(pilot_xds_pushcontext_init_time_bucket[5m]))

# Config validation time
histogram_quantile(0.99, rate(galley_validation_http_duration_bucket[5m]))
```

#### Endpoint discovery
```promql
# Endpoint update frequency
rate(pilot_eds_no_instances[5m])

# Service discovery errors
rate(pilot_total_xds_rejects[5m])
```

### Citadel (jeśli włączone)

#### Certificate generation
```promql
# Cert generation time
histogram_quantile(0.99, rate(citadel_server_csr_processing_time_bucket[5m]))

# Certificate lifetimes
citadel_server_certificate_expiry_time
```

## Metryki KWOK

### Controller performance
```promql
# KWOK controller processing time
kwok_controller_reconcile_duration_seconds

# Number of fake nodes managed
kwok_controller_nodes_total

# Number of fake pods managed  
kwok_controller_pods_total
```

## Metryki systemu (Node-level)

### CPU i Memory
```promql
# CPU usage
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Memory pressure
node_memory_MemAvailable_bytes < 1e9
```

### Network
```promql
# Network throughput
rate(node_network_receive_bytes_total[5m])
rate(node_network_transmit_bytes_total[5m])

# Network errors
rate(node_network_receive_errs_total[5m])
rate(node_network_transmit_errs_total[5m])
```

### Disk I/O
```promql
# Disk utilization
rate(node_disk_io_time_seconds_total[5m])

# Disk read/write bytes
rate(node_disk_read_bytes_total[5m])
rate(node_disk_written_bytes_total[5m])
```

## Kluczowe SLIs/SLOs dla testów wydajności

### API Server
- **Latencja**: p99 < 1s dla non-watch requests
- **Dostępność**: > 99.9%
- **Throughput**: > 1000 QPS

### etcd
- **Latencja**: p99 < 200ms
- **Backend latencja**: p99 < 100ms
- **WAL fsync**: p99 < 10ms

### Scheduler
- **Scheduling latency**: p99 < 100ms dla prostych podów
- **Queue depth**: < 100 podów oczekujących

### CoreDNS
- **Query latency**: p99 < 100ms
- **Cache hit ratio**: > 80%
- **Error rate**: < 1%

### Istio Pilot
- **XDS push time**: p99 < 10s
- **Config propagation**: < 30s do wszystkich proxy
- **Memory usage**: < 2GB dla 1000+ services

## Alerty i troubleshooting

### Krytyczne alerty
```yaml
# API Server down
up{job="kubernetes-apiservers"} == 0

# High API latency
histogram_quantile(0.99, rate(apiserver_request_duration_seconds_bucket{verb!="WATCH"}[5m])) > 1

# etcd high latency
histogram_quantile(0.99, rate(etcd_request_duration_seconds_bucket[5m])) > 0.2

# High scheduler queue
scheduler_pending_pods > 100

# CoreDNS down
up{job="coredns"} == 0
```

### Performance degradation indicators
```promql
# API Server error rate spike
increase(apiserver_request_total{code=~"5.."}[5m]) > 10

# etcd backend commit latency spike
histogram_quantile(0.99, rate(etcd_disk_backend_commit_duration_seconds_bucket[5m])) > 0.1

# Scheduler latency increase
histogram_quantile(0.99, rate(scheduler_scheduling_duration_seconds_bucket[5m])) > 0.5

# Memory pressure
(node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) < 0.1
```

## Użyteczne zapytania dla analizy wydajności

### Top consumers
```promql
# Top API resources by request count
topk(10, sum(rate(apiserver_request_total[5m])) by (resource))

# Top schedulers by latency
topk(5, histogram_quantile(0.99, rate(scheduler_scheduling_duration_seconds_bucket[5m])) by (operation))

# Top controllers by work queue depth
topk(10, workqueue_depth by (name))
```

### Time series dla trend analysis
```promql
# API latency trend over time
histogram_quantile(0.99, rate(apiserver_request_duration_seconds_bucket{verb!="WATCH"}[5m]))[1h:1m]

# etcd performance trend
histogram_quantile(0.99, rate(etcd_request_duration_seconds_bucket[5m]))[1h:1m]

# Scheduler performance trend
histogram_quantile(0.99, rate(scheduler_scheduling_duration_seconds_bucket[5m]))[1h:1m]
```

## Dashboardy w Grafana

### Kubernetes Control Plane Dashboard
- API Server latency i throughput
- etcd performance
- Scheduler queue i latency
- Controller Manager work queues
- CoreDNS performance

### Istio Control Plane Dashboard  
- Pilot XDS push metrics
- Configuration propagation time
- Connected proxies count
- Certificate generation metrics

### KWOK Performance Dashboard
- Fake nodes/pods count
- Controller reconciliation time
- Memory i CPU usage

## Najlepsze praktyki monitorowania

1. **Ustaw odpowiednie retention**: 24h dla detailed metrics, 7d dla aggregates
2. **Używaj recording rules**: Pre-compute expensive queries
3. **Monitoruj trendy**: Nie tylko current values
4. **Ustaw sensible alerting**: Avoid alert fatigue
5. **Document baselines**: Establish normal performance ranges
6. **Monitor cardinality**: Avoid high-cardinality metrics explosion

## Interpretacja wyników testów

### Oczekiwane wartości dla środowiska testowego:
- **API Server p99 latency**: 100-500ms (zależnie od load)
- **etcd p99 latency**: 10-50ms (SSD storage)
- **Scheduler p99 latency**: 10-100ms
- **KWOK overhead**: Minimalny vs real kubelet
- **Istio Pilot push time**: 1-5s dla small meshes

### Red flags (wymagające uwagi):
- API Server p99 > 1s stale
- etcd p99 > 200ms
- Scheduler queue depth > 100 przez > 5min
- Memory usage > 80% przez dłuższy czas
- High API Server error rate (>1%)

Ten przewodnik służy jako podstawa do analizy wydajności w środowisku testowym z KWOK i Istio. 