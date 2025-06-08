#!/bin/bash

for i in $(seq 1 10); do
    node_name="kwok-node-$(printf "%03d" $i)"
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Node
metadata:
  name: ${node_name}
  labels:
    type: kwok
    node.kubernetes.io/instance-type: m5.large
    beta.kubernetes.io/arch: amd64
    beta.kubernetes.io/os: linux
    kubernetes.io/arch: amd64
    kubernetes.io/hostname: ${node_name}
    kubernetes.io/os: linux
    kwok.x-k8s.io/node: ${node_name}
  annotations:
    kwok.x-k8s.io/node: ${node_name}
    node.alpha.kubernetes.io/ttl: "0"
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
  nodeInfo:
    architecture: amd64
    bootID: ""
    containerRuntimeVersion: ""
    kernelVersion: ""
    kubeProxyVersion: v1.32.0
    kubeletVersion: v1.32.0
    machineID: ""
    operatingSystem: linux
    osImage: ""
    systemUUID: ""
  phase: Running
EOF
done

echo "Utworzono 10 fake nodes!"
kubectl get nodes --selector=type=kwok 