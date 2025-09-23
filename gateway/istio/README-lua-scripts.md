# Lua Scripts Configuration

This directory contains Lua scripts that are used by Envoy filters in the Istio gateway.

## Files

- `tier-injector.lua` - Lua script that injects customer tier headers
- `03-configmap-lua-scripts.yaml` - ConfigMap template for the Lua scripts
- `02-gateway-volume-mount.yaml` - Strategic merge patch to mount the ConfigMap
- `04-envoyfilter-tier-injector.yaml` - EnvoyFilter that references the external Lua script

## Deployment Steps

1. **Create the ConfigMap from the Lua file:**
   ```bash
   kubectl create configmap lua-scripts --from-file=tier-injector.lua --namespace=default
   ```

2. **Apply the volume mount patch:**
   ```bash
   kubectl patch deployment istio-demo-gateway-istio --patch-file 02-gateway-volume-mount.yaml --type strategic
   ```

3. **Apply the EnvoyFilter:**
   ```bash
   kubectl apply -f 04-envoyfilter-tier-injector.yaml
   ```

## How It Works

The EnvoyFilter references the Lua script at `/etc/lua-scripts/tier-injector.lua`. The volume mount patch ensures the ConfigMap is mounted at that path in the `istio-demo-gateway-istio` deployment.
