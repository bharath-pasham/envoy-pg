#!/bin/bash

# Minikube Cluster Restoration Script
# This script restores all resources that were backed up from your minikube cluster

set -e

echo "Starting minikube cluster restoration..."

# Check if minikube is running
if ! minikube status >/dev/null 2>&1; then
    echo "Starting minikube..."
    minikube start
fi

# Wait for cluster to be ready
echo "Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# Create backup directory if it doesn't exist
BACKUP_DIR="$(dirname "$0")"
cd "$BACKUP_DIR"

echo "Restoring resources from: $BACKUP_DIR"

# Restore resources in order of dependencies
echo "Restoring ServiceAccounts..."
if [ -f "serviceaccounts.yaml" ]; then
    kubectl apply -f serviceaccounts.yaml
fi

echo "Restoring ClusterRoles..."
if [ -f "clusterroles.yaml" ]; then
    kubectl apply -f clusterroles.yaml
fi

echo "Restoring ClusterRoleBindings..."
if [ -f "clusterrolebindings.yaml" ]; then
    kubectl apply -f clusterrolebindings.yaml
fi

echo "Restoring Roles..."
if [ -f "roles.yaml" ]; then
    kubectl apply -f roles.yaml
fi

echo "Restoring RoleBindings..."
if [ -f "rolebindings.yaml" ]; then
    kubectl apply -f rolebindings.yaml
fi

echo "Restoring ConfigMaps..."
if [ -f "configmaps.yaml" ]; then
    kubectl apply -f configmaps.yaml
fi

echo "Restoring Secrets..."
if [ -f "secrets.yaml" ]; then
    kubectl apply -f secrets.yaml
fi

echo "Restoring PersistentVolumes..."
if [ -f "persistentvolumes.yaml" ]; then
    kubectl apply -f persistentvolumes.yaml
fi

echo "Restoring PersistentVolumeClaims..."
if [ -f "persistentvolumeclaims.yaml" ]; then
    kubectl apply -f persistentvolumeclaims.yaml
fi

echo "Restoring main resources (Deployments, Services, etc.)..."
if [ -f "all-resources.yaml" ]; then
    kubectl apply -f all-resources.yaml
fi

echo "Restoring NetworkPolicies..."
if [ -f "networkpolicies.yaml" ]; then
    kubectl apply -f networkpolicies.yaml
fi

echo "Restoring Ingresses..."
if [ -f "ingresses.yaml" ]; then
    kubectl apply -f ingresses.yaml
fi

echo "Restoration completed!"
echo "Checking cluster status..."
kubectl get nodes
kubectl get pods --all-namespaces

echo ""
echo "All resources have been restored to your minikube cluster."
echo "You may need to wait a few moments for all pods to become ready."