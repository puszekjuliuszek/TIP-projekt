#!/bin/bash

set -e

# Kolory dla outputu
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Konfiguracja
CLUSTER_NAME="${CLUSTER_NAME:-kwok-performance-test}"
REGION="${AWS_REGION:-us-west-2}"
NODE_GROUP_NAME="${NODE_GROUP_NAME:-primary-nodes}"
INSTANCE_TYPE="${INSTANCE_TYPE:-m5.large}"
NODE_COUNT="${NODE_COUNT:-3}"

echo -e "${GREEN}🚀 Rozpoczynam instalację klastra EKS...${NC}"

# Sprawdź czy eksctl jest zainstalowane
if ! command -v eksctl &> /dev/null; then
    echo -e "${YELLOW}⚠️  eksctl nie jest zainstalowane. Instaluję...${NC}"
    
    # Instalacja eksctl dla macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            brew tap weaveworks/tap
            brew install weaveworks/tap/eksctl
        else
            curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
            sudo mv /tmp/eksctl /usr/local/bin
        fi
    else
        # Linux
        curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
        sudo mv /tmp/eksctl /usr/local/bin
    fi
fi

# Sprawdź czy kubectl jest zainstalowane
if ! command -v kubectl &> /dev/null; then
    echo -e "${YELLOW}⚠️  kubectl nie jest zainstalowane. Instaluję...${NC}"
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            brew install kubectl
        else
            curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl"
            chmod +x kubectl
            sudo mv kubectl /usr/local/bin/
        fi
    else
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/
    fi
fi

# Sprawdź połączenie z AWS
echo -e "${GREEN}🔍 Sprawdzam połączenie z AWS...${NC}"
aws sts get-caller-identity || {
    echo -e "${RED}❌ Błąd: Nie można połączyć się z AWS. Sprawdź konfigurację AWS CLI.${NC}"
    exit 1
}

# Sprawdź czy klaster już istnieje
if eksctl get cluster --name=$CLUSTER_NAME --region=$REGION &>/dev/null; then
    echo -e "${YELLOW}⚠️  Klaster $CLUSTER_NAME już istnieje w regionie $REGION${NC}"
    read -p "Czy chcesz go usunąć i utworzyć nowy? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}🗑️  Usuwam istniejący klaster...${NC}"
        eksctl delete cluster --name=$CLUSTER_NAME --region=$REGION --wait
    else
        echo -e "${GREEN}✅ Używam istniejącego klastra${NC}"
        aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME
        exit 0
    fi
fi

# Tworzenie klastera EKS
echo -e "${GREEN}🏗️  Tworzę klaster EKS: $CLUSTER_NAME w regionie $REGION...${NC}"
echo -e "${YELLOW}⏱️  To może potrwać 15-20 minut...${NC}"

# Generowanie konfiguracji klastra
cat > configs/cluster-config.yaml << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ${CLUSTER_NAME}
  region: ${REGION}
  version: "1.27"

# Konfiguracja control plane będzie automatyczna

# Managed node groups
managedNodeGroups:
  - name: ${NODE_GROUP_NAME}
    instanceType: ${INSTANCE_TYPE}
    minSize: 1
    maxSize: 10
    desiredCapacity: ${NODE_COUNT}
    volumeSize: 50
    ssh:
      allow: false
    labels:
      role: worker
    tags:
      Project: "KWOK-Performance-Test"
      Environment: "Testing"
    
    # Optimalizacje dla wydajności
    preBootstrapCommands:
      - "echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf"
      - "echo 'net.bridge.bridge-nf-call-iptables = 1' >> /etc/sysctl.conf"
      - "sysctl -p"

# Addons potrzebne dla KWOK i monitorowania
addons:
  - name: vpc-cni
  - name: coredns
  - name: kube-proxy
  - name: aws-ebs-csi-driver

# CloudWatch logging
cloudWatch:
  clusterLogging:
    enableTypes: ["api", "audit", "authenticator", "controllerManager", "scheduler"]

# IAM dla service accounts
iam:
  withOIDC: true
  serviceAccounts:
    - metadata:
        name: aws-load-balancer-controller
        namespace: kube-system
      wellKnownPolicies:
        awsLoadBalancerController: true
    - metadata:
        name: ebs-csi-controller-sa
        namespace: kube-system
      wellKnownPolicies:
        ebsCSIController: true
    - metadata:
        name: cluster-autoscaler
        namespace: kube-system
      wellKnownPolicies:
        autoScaler: true

EOF

# Uruchomienie tworzenia klastra
eksctl create cluster -f configs/cluster-config.yaml

# Sprawdzenie statusu klastra
echo -e "${GREEN}✅ Klaster został utworzony! Sprawdzam status...${NC}"
kubectl get nodes
kubectl get pods --all-namespaces

# Instalacja AWS Load Balancer Controller
echo -e "${GREEN}🔧 Instaluję AWS Load Balancer Controller...${NC}"
curl -o aws-load-balancer-controller-iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.4.4/docs/install/iam_policy.json

aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://aws-load-balancer-controller-iam-policy.json \
    --region $REGION 2>/dev/null || echo "Policy already exists"

# Instalacja przez Helm
if ! command -v helm &> /dev/null; then
    echo -e "${YELLOW}⚠️  Helm nie jest zainstalowany. Instaluję...${NC}"
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=${CLUSTER_NAME} \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=${REGION} \
  --set vpcId=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${REGION} --query "cluster.resourcesVpcConfig.vpcId" --output text)

# Instalacja Metrics Server
echo -e "${GREEN}📊 Instaluję Metrics Server...${NC}"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Oczekiwanie na uruchomienie podstawowych komponentów
echo -e "${GREEN}⏳ Oczekuję na uruchomienie podstawowych komponentów...${NC}"
kubectl wait --for=condition=ready pod -l k8s-app=metrics-server -n kube-system --timeout=300s

# Zapisanie informacji o klastrze
echo -e "${GREEN}💾 Zapisuję informacje o klastrze...${NC}"
cat > cluster-info.txt << EOF
Klaster EKS: ${CLUSTER_NAME}
Region: ${REGION}
Node Group: ${NODE_GROUP_NAME}
Instance Type: ${INSTANCE_TYPE}
Liczba węzłów: ${NODE_COUNT}

Endpoint: $(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${REGION} --query "cluster.endpoint" --output text)
Wersja: $(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${REGION} --query "cluster.version" --output text)

Utworzono: $(date)
EOF

echo -e "${GREEN}🎉 Klaster EKS został pomyślnie utworzony!${NC}"
echo -e "${GREEN}📁 Informacje o klastrze zapisane w cluster-info.txt${NC}"
echo -e "${GREEN}➡️  Następny krok: ./scripts/02-install-kwok.sh${NC}"

# Cleanup
rm -f aws-load-balancer-controller-iam-policy.json 