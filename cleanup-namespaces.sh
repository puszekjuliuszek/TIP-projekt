#!/bin/bash

set -e

# Kolory dla outputu
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🧹 Cleanup zawieszonych namespace'ów...${NC}"

# Funkcja do forsowania usunięcia namespace
force_delete_namespace() {
    local ns=$1
    echo -e "${YELLOW}🗑️  Forsując usunięcie namespace: $ns${NC}"
    
    # Usuń wszystkie finalizery
    kubectl get namespace $ns -o json | \
        jq '.spec.finalizers = []' | \
        kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f -
}

# Sprawdź zawieszony namespace isotope
if kubectl get namespace isotope 2>/dev/null | grep -q "Terminating"; then
    echo -e "${YELLOW}⚠️  Znaleziono zawieszony namespace 'isotope'${NC}"
    force_delete_namespace isotope
    sleep 5
    
    if kubectl get namespace isotope &>/dev/null; then
        echo -e "${RED}❌ Nie udało się usunąć namespace isotope${NC}"
    else
        echo -e "${GREEN}✅ Namespace isotope usunięty${NC}"
    fi
fi

# Sprawdź inne zawieszuone namespace'y
echo -e "${GREEN}🔍 Sprawdzam inne zawieszuone namespace'y...${NC}"
terminating_ns=$(kubectl get namespaces | grep Terminating | awk '{print $1}' || true)

if [ -n "$terminating_ns" ]; then
    echo -e "${YELLOW}⚠️  Znaleziono zawieszuone namespace'y: $terminating_ns${NC}"
    for ns in $terminating_ns; do
        force_delete_namespace $ns
    done
else
    echo -e "${GREEN}✅ Brak zawieszuonych namespace'ów${NC}"
fi

echo -e "${GREEN}🎉 Cleanup zakończony!${NC}" 