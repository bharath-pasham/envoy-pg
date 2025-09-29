# Minikube Backup and Restore

This directory contains a complete backup of your minikube cluster resources.

## Files

- `all-resources.yaml` - All basic Kubernetes resources (pods, services, deployments, etc.)
- `configmaps.yaml` - All ConfigMaps
- `secrets.yaml` - All Secrets
- `persistentvolumes.yaml` - All PersistentVolumes
- `persistentvolumeclaims.yaml` - All PersistentVolumeClaims
- `ingresses.yaml` - All Ingresses
- `networkpolicies.yaml` - All NetworkPolicies
- `serviceaccounts.yaml` - All ServiceAccounts
- `roles.yaml` - All Roles
- `rolebindings.yaml` - All RoleBindings
- `clusterroles.yaml` - All ClusterRoles
- `clusterrolebindings.yaml` - All ClusterRoleBindings
- `restore.sh` - Automated restoration script

## How to Restore

1. Start minikube (if not already running):
   ```bash
   minikube start
   ```

2. Run the restoration script:
   ```bash
   ./restore.sh
   ```

The script will automatically restore all resources in the correct order to handle dependencies.

## Manual Restoration

If you prefer to restore manually, apply the files in this order:

1. `serviceaccounts.yaml`
2. `clusterroles.yaml`
3. `clusterrolebindings.yaml`
4. `roles.yaml`
5. `rolebindings.yaml`
6. `configmaps.yaml`
7. `secrets.yaml`
8. `persistentvolumes.yaml`
9. `persistentvolumeclaims.yaml`
10. `all-resources.yaml`
11. `networkpolicies.yaml`
12. `ingresses.yaml`

Example:
```bash
kubectl apply -f serviceaccounts.yaml
kubectl apply -f configmaps.yaml
# ... etc
```