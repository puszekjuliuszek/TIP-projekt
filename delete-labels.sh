#!/bin/bash

# This script removes all labels from all Kubernetes nodes.

set -e

echo "Removing all labels from all nodes..."

for node in $(kubectl get nodes -o name | sed 's|node/||'); do
  labels=$(kubectl get node "$node" --show-labels | awk 'NR==2 {print $6}' | tr ',' '\n' | cut -d'=' -f1)
  for label in $labels; do
    # Skip the required Kubernetes labels (like kubernetes.io/hostname)
    if [[ "$label" == "kubernetes.io/"* ]] || [[ "$label" == "node-role.kubernetes.io/"* ]]; then
      continue
    fi
    kubectl label node "$node" "$label"- --overwrite
  done
done

echo "All non-essential labels removed from all nodes."