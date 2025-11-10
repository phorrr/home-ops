# k3d Cluster Bootstrap Guide

This guide covers the deployment and bootstrapping of k3d clusters on Unraid nodes for the home-ops infrastructure.

## Overview

The home-ops repository supports multiple k3d clusters running on Unraid nodes:
- **zapp-k3d**: Primary k3d cluster on REDACTED_DOMAIN
- **offsite-k3d**: Offsite k3d cluster on REDACTED_DOMAIN

Each cluster is:
- **Standalone**: Single-node k3d cluster running in Docker
- **GitOps-managed**: Flux CD for automated deployments via Flux Operator
- **Persistent**: Survives Unraid reboots via User Scripts plugin
- **Isolated**: Separate 1Password vaults and External Secrets configuration
- **Lightweight**: Uses k3s built-in Flannel CNI (safe for Unraid kernel)

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│ Unraid Host (REDACTED_DOMAIN)                            │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │ Docker Engine                                    │  │
│  │  ┌────────────────────────────────────────────┐  │  │
│  │  │ k3d-zapp-k3d-server-0                     │  │  │
│  │  │ Image: rancher/k3s:v1.34.1-k3s1           │  │  │
│  │  │ Restart: unless-stopped                    │  │  │
│  │  │                                            │  │  │
│  │  │ k3s components:                            │  │  │
│  │  │ • API Server (exposed :6443)               │  │  │
│  │  │ • Flannel CNI (default vxlan)              │  │  │
│  │  │ • local-path provisioner                   │  │  │
│  │  │                                            │  │  │
│  │  │ Deployed workloads:                        │  │  │
│  │  │ • CoreDNS (Helm managed)                   │  │  │
│  │  │ • cert-manager                             │  │  │
│  │  │ • 1Password Connect                        │  │  │
│  │  │ • External Secrets Operator                │  │  │
│  │  │ • Flux Operator + Instance                 │  │  │
│  │  │ • Application Workloads                    │  │  │
│  │  └────────────────────────────────────────────┘  │  │
│  │  ┌────────────────────────────────────────────┐  │  │
│  │  │ k3d-zapp-k3d-serverlb                     │  │  │
│  │  │ (Port mapping proxy)                       │  │  │
│  │  │ Restart: unless-stopped                    │  │  │
│  │  │ • 6443:6443 (Kubernetes API)               │  │  │
│  │  │ • 80:30080 (HTTP → NodePort)               │  │  │
│  │  │ • 443:30443 (HTTPS → NodePort)             │  │  │
│  │  └────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  Persistent Volumes (mounted into containers):          │
│  • /mnt/user/appdata/k3d-zapp/storage                   │
│    → /var/lib/rancher/k3s/storage (PVs from local-path) │
│  • /mnt/user/appdata/k3d-zapp/data                      │
│    → /data (direct hostPath mounts)                     │
│  • /boot/bin/ (k3d, kubectl, flux binaries)             │
│                                                         │
│  Auto-start: User Scripts plugin runs at array startup  │
└─────────────────────────────────────────────────────────┘
```

## Prerequisites

### On Unraid Nodes

1. **Docker**: Must be installed and running (built-in with Unraid)
2. **Python 3**: Automatically installed by Ansible playbook (Slackware packages)
3. **SSH Access**: Root SSH access configured
4. **Storage**: Sufficient space in `/mnt/user/appdata/` (approximately 5-10GB per cluster)
5. **User Scripts Plugin**: Recommended for auto-start on boot (Community Applications)

### On Management Machine (Your Local Machine)

1. **Ansible**: Version 2.10+ with kubernetes.core collection
2. **kubectl**: Kubernetes CLI (version 1.34.0+)
3. **helmfile**: For Helm chart deployment during bootstrap
4. **minijinja-cli**: Template rendering for bootstrap resources
5. **1Password CLI (op)**: For secrets management during bootstrap
6. **mise**: For running bootstrap tasks (optional but recommended)

## Step 1: Prepare 1Password Secrets

Before deploying, create separate 1Password vaults for each cluster, each with a `CLUSTER_VARS` item:

### zapp-k3d Vault
Create a vault for the zapp-k3d cluster with a `CLUSTER_VARS` item containing:
```
INTERNAL_DOMAIN=REDACTED_INTERNAL_DOMAIN
TIMEZONE=UTC
# Add other cluster-specific variables as needed
```

### offsite-k3d Vault
Create a vault for the offsite-k3d cluster with a `CLUSTER_VARS` item containing:
```
INTERNAL_DOMAIN=REDACTED_INTERNAL_DOMAIN
TIMEZONE=UTC
# Add other cluster-specific variables as needed
```

**Note**: Each cluster will have its own 1Password vault, and each vault contains the same item name (`CLUSTER_VARS`). The ClusterSecretStore configuration will point to the appropriate vault per cluster.

## Step 2: Deploy k3d Clusters via Ansible

### What the Playbook Does

The `ansible/deploy-k3d-clusters.yaml` playbook performs a complete deployment:

**Phase 1: Python Bootstrap** (for Unraid's Slackware)
1. Checks if Python 3 is installed
2. Downloads and installs Python 3.9.10 from Slackware packages
3. Installs OpenSSL 1.1 and libffi dependencies
4. Downloads packages to `/boot/extra/` for persistence across reboots

**Phase 2: k3d Cluster Deployment** (role: `k3d-unraid`)
1. Downloads binaries to persistent storage:
   - k3d v5.8.3 → `/boot/bin/k3d`
   - kubectl v1.34.0 → `/boot/bin/kubectl`
   - flux v2.7.0 → `/boot/bin/flux`
2. Copies binaries to `/usr/local/bin/` (RAM, lost on reboot)
3. Creates persistent storage directories:
   - `/mnt/user/appdata/k3d-{cluster}/storage` (for PVs)
   - `/mnt/user/appdata/k3d-{cluster}/data` (for hostPath mounts)
4. Renders k3d cluster config from template
5. Creates k3d cluster using config
6. Updates Docker containers to `restart: unless-stopped`
7. Deploys User Scripts plugin startup script

**Phase 3: Post-Deployment**
1. Waits for cluster to be ready
2. Displays next steps for kubeconfig and Flux bootstrap

### Deploy Both Clusters

```bash
# From the repository root
ansible-playbook -i ansible/inventory.yaml ansible/deploy-k3d-clusters.yaml

# Deploy to specific node only
ansible-playbook -i ansible/inventory.yaml ansible/deploy-k3d-clusters.yaml --limit unraid-zapp
ansible-playbook -i ansible/inventory.yaml ansible/deploy-k3d-clusters.yaml --limit unraid-offsite
```

### Verify Deployment

SSH to the Unraid node and verify:

```bash
# Check k3d cluster is running
k3d cluster list

# Check Docker containers
docker ps | grep k3d

# Verify cluster health
kubectl --context k3d-zapp-k3d get nodes
kubectl --context k3d-zapp-k3d get pods -A
```

## Step 3: Setup Kubeconfig Access

The k3d cluster exposes its Kubernetes API server on **port 6443** via the `k3d-{cluster}-serverlb` container, making it accessible from your local machine.

### Option A: Using Ansible Playbook (Recommended)

The repository includes an Ansible playbook to automatically setup kubeconfig access:

```bash
# Setup kubeconfig for all k3d clusters
ansible-playbook -i ansible/inventory.yaml ansible/setup-kubecontexts.yaml

# This will:
# 1. Extract kubeconfig from each k3d cluster
# 2. Update server URL from REDACTED_PUBLIC_IP:6443 to {hostname}:6443
# 3. Merge into your local ~/.kube/config
# 4. Verify connectivity to each cluster
```

### Option B: Manual Setup

```bash
# SSH to Unraid and get the kubeconfig
ssh root@REDACTED_DOMAIN "k3d kubeconfig get zapp-k3d" > ~/.kube/zapp-k3d-config

# The kubeconfig will reference REDACTED_PUBLIC_IP:6443, update to the actual hostname
sed -i '' 's/REDACTED_PUBLIC_IP/REDACTED_DOMAIN/g' ~/.kube/zapp-k3d-config

# Merge into your main kubeconfig
KUBECONFIG=~/.kube/config:~/.kube/zapp-k3d-config kubectl config view --flatten > ~/.kube/config-merged
mv ~/.kube/config-merged ~/.kube/config

# Verify access
kubectl --context k3d-zapp-k3d get nodes
```

### API Server Accessibility

**Kubernetes API**: `https://REDACTED_DOMAIN:6443`
- Exposed by the `k3d-zapp-k3d-serverlb` container (port mapping proxy)
- Accessible from your local network
- Certificate includes the Unraid hostname via `--tls-san` flag
- Context name: `k3d-zapp-k3d`

**For offsite-k3d**:
- API endpoint: `https://REDACTED_DOMAIN:6443`
- Context name: `k3d-offsite-k3d`

## Step 4: Bootstrap Applications with Ansible

The repository uses an Ansible playbook (`ansible/bootstrap-k3d-apps.yaml`) to bootstrap core applications. This runs from your **local machine** and connects to the cluster via kubectl.

### What the Bootstrap Playbook Does

The `ansible/bootstrap-k3d-apps.yaml` playbook performs:

**Phase 1: Pre-flight Checks**
1. Verifies required CLI tools: `kubectl`, `op`, `helmfile`, `minijinja-cli`
2. Checks bootstrap directory exists (`bootstrap/{cluster-name}/`)
3. Verifies kubectl context is available
4. Waits for cluster nodes to be ready

**Phase 2: Secrets Rendering**
1. Fetches `CLUSTER_VARS` from 1Password vault (e.g., `zapp-k3d` vault)
2. Fetches and decodes GitHub deploy key for Flux
3. Renders `bootstrap/{cluster}/resources.yaml.j2` using `minijinja-cli`
4. Injects 1Password secrets using `op inject`
5. Creates namespaces and secrets: `cert-manager`, `external-secrets`, `flux-system`

**Phase 3: Helm Chart Installation**
Runs `helmfile apply` using `bootstrap/{cluster}/helmfile.yaml`:
1. **CoreDNS** - Cluster DNS (Helm-managed for consistency)
2. **cert-manager** - Certificate management
3. **1Password Connect** - Secret backend
4. **External Secrets Operator** - Syncs secrets from 1Password
5. **Flux Operator** - GitOps operator
6. **Flux Instance** - Flux CD deployment

**Phase 4: Validation**
1. Waits for pods to be Ready in each namespace
2. Displays final cluster status

### Prerequisites

**IMPORTANT**: Before running bootstrap, you must create the application Helm values files referenced by the helmfile:

- `kubernetes/clusters/{cluster}/apps/kube-system/coredns/app/helm/values.yaml`
- `kubernetes/clusters/{cluster}/apps/cert-manager/cert-manager/app/helm/values.yaml`
- `kubernetes/clusters/{cluster}/apps/external-secrets/onepassword/app/helm/values.yaml`
- `kubernetes/clusters/{cluster}/apps/external-secrets/external-secrets/app/helm/values.yaml`
- `kubernetes/clusters/{cluster}/apps/flux-system/flux-operator/app/helm/values.yaml`
- `kubernetes/clusters/{cluster}/apps/flux-system/flux-instance/app/helm/values.yaml`

You can copy and adapt these from the `home-k3s` cluster as a starting point.

**Note**: k3d clusters use **k3s built-in Flannel CNI** (default vxlan mode). Unlike home-k3s which disables Flannel for Cilium, k3d clusters keep the lightweight Flannel CNI for compatibility with Unraid's kernel.

### Bootstrap zapp-k3d

```bash
# 1. Authenticate with 1Password CLI
eval $(op signin)

# 2. Set environment and run bootstrap
VAULT_NAME=zapp-k3d ansible-playbook \
  -i ansible/inventory.yaml \
  ansible/bootstrap-k3d-apps.yaml \
  -e cluster_name=zapp-k3d

# Or use the mise task wrapper:
mise run bootstrap-apps zapp-k3d
```

### Bootstrap offsite-k3d

```bash
# Authenticate with 1Password CLI
eval $(op signin)

# Run bootstrap
VAULT_NAME=offsite-k3d ansible-playbook \
  -i ansible/inventory.yaml \
  ansible/bootstrap-k3d-apps.yaml \
  -e cluster_name=offsite-k3d

# Or use mise:
mise run bootstrap-apps offsite-k3d
```

### Verify Bootstrap

```bash
# Check all pods are running
kubectl --context k3d-zapp-k3d get pods -A

# Verify Flux installation
flux --context=k3d-zapp-k3d get all -A

# Check External Secrets
kubectl --context k3d-zapp-k3d get externalsecret -n flux-system

# Check for any errors
flux --context=k3d-zapp-k3d logs --all-namespaces --level=error
```

## Step 5: Validate Setup

The bootstrap process has already installed:
- ✅ Flannel CNI (k3s built-in, vxlan mode)
- ✅ CoreDNS (Helm-managed)
- ✅ local-path storage provisioner (k3s built-in)
- ✅ cert-manager
- ✅ 1Password Connect
- ✅ External Secrets Operator
- ✅ Flux Operator and Instance

### Test Flux Reconciliation

```bash
# Force reconciliation
flux --context=k3d-zapp-k3d reconcile kustomization cluster-infrastructure --with-source
flux --context=k3d-zapp-k3d reconcile kustomization cluster-apps --with-source

# Check status
flux --context=k3d-zapp-k3d get kustomizations
```

### Test Secrets

```bash
# Verify cluster-vars secret exists
kubectl --context k3d-zapp-k3d get secret cluster-vars -n flux-system

# Check ExternalSecret status
kubectl --context k3d-zapp-k3d get externalsecret cluster-vars -n flux-system -o yaml
```

### Test Persistence

```bash
# Reboot Unraid node
ssh root@REDACTED_DOMAIN "reboot"

# Wait for reboot (~2-3 minutes)

# Verify cluster auto-started
ssh root@REDACTED_DOMAIN "k3d cluster list"

# Check applications are running
kubectl --context k3d-zapp-k3d get pods -A
```

## Storage Options

The k3d clusters provide two methods for persistent storage on the Unraid host:

### Option 1: local-path StorageClass (Recommended)

The k3s local-path provisioner is enabled by default and provides dynamic PersistentVolume provisioning using hostPath:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-app-data
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 10Gi
```

**Storage Location:**
- **Inside container**: `/var/lib/rancher/k3s/storage/pvc-<uuid>`
- **On Unraid host**: `/mnt/user/appdata/k3d-zapp/storage/pvc-<uuid>`

**Benefits:**
- Automatic PV provisioning
- Survives pod restarts and cluster recreations
- Clean lifecycle management (deleted when PVC is deleted)

### Option 2: Direct hostPath Volumes

For applications that need access to specific Unraid directories, use the `/data` mount point that's mapped into the cluster:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
        - name: app
          volumeMounts:
            - name: downloads
              mountPath: /downloads
      volumes:
        - name: downloads
          hostPath:
            path: /data/downloads  # Maps to /mnt/user/appdata/k3d-zapp/data/downloads on Unraid
            type: DirectoryOrCreate
```

**Storage Location:**
- **Inside container**: `/data/*`
- **On Unraid host**: `/mnt/user/appdata/k3d-zapp/data/*` (zapp-k3d) or `/mnt/user/appdata/k3d-offsite/data/*` (offsite-k3d)

**Use Cases:**
- Sharing directories between multiple pods
- Accessing existing Unraid shares
- Media files for Plex/Jellyfin
- Download directories for Sonarr/Radarr/qBittorrent

**Example Directory Structure:**
```bash
# On Unraid host
/mnt/user/appdata/k3d-zapp/
├── storage/           # local-path provisioner PVs
│   └── pvc-<uuid>/
└── data/              # Direct hostPath mounts
    ├── downloads/
    ├── media/
    └── config/
```

### Persistence Guarantees

Both storage methods persist across:
- ✅ Pod restarts
- ✅ Deployment updates
- ✅ Unraid host reboots
- ✅ k3d cluster restarts
- ✅ k3d cluster deletion and recreation (as long as Ansible storage directories remain)

**Important**: Both storage directories are created by Ansible and mounted into the k3d Docker container. As long as you don't delete `/mnt/user/appdata/k3d-*/` on the Unraid host, your data persists.

## Testing Infrastructure Changes

Use the updated flux-test.sh script:

```bash
# Test zapp-k3d cluster
./mise-tasks/flux-test.sh zapp-k3d

# Test offsite-k3d cluster
./mise-tasks/flux-test.sh offsite-k3d

# Test home-k3s cluster (default)
./mise-tasks/flux-test.sh
```

## Troubleshooting

### Cluster Won't Start After Reboot

The User Scripts plugin runs `/boot/config/plugins/user.scripts/scripts/k3d-start/script` at array startup. This script:
1. Copies binaries from `/boot/bin/` to `/usr/local/bin/`
2. Waits for Docker to be ready
3. Starts or creates the k3d cluster
4. Updates Docker restart policies

```bash
# SSH to Unraid node
ssh root@REDACTED_DOMAIN

# Check User Scripts log
cat /tmp/user.scripts/tmpScripts/k3d-start/log.txt

# Check if binaries are in place
which k3d kubectl flux

# Check Docker containers status
docker ps -a | grep k3d

# Manually start cluster if needed
k3d cluster start zapp-k3d

# Or manually run the startup script
bash /boot/config/plugins/user.scripts/scripts/k3d-start/script
```

### Flux Reconciliation Issues

```bash
# Check Flux controller logs
kubectl --context k3d-zapp-k3d logs -n flux-system deploy/kustomize-controller

# Check source-controller for Git issues
kubectl --context k3d-zapp-k3d logs -n flux-system deploy/source-controller

# Suspend and resume problematic kustomization
flux --context=k3d-zapp-k3d suspend kustomization <name> -n flux-system
flux --context=k3d-zapp-k3d resume kustomization <name> -n flux-system
```

### ExternalSecret Not Syncing

```bash
# Check ClusterSecretStore
kubectl --context k3d-zapp-k3d get clustersecretstore

# Check ExternalSecret status
kubectl --context k3d-zapp-k3d describe externalsecret cluster-vars -n flux-system

# Check external-secrets-operator logs
kubectl --context k3d-zapp-k3d logs -n external-secrets deploy/external-secrets
```

### Storage Issues

```bash
# SSH to Unraid node
ssh root@REDACTED_DOMAIN

# Check storage directories
ls -lah /mnt/user/appdata/k3d-zapp/
df -h /mnt/user/appdata/

# Check volume mounts in containers
docker inspect k3d-zapp-k3d-server-0 | grep -A 10 Mounts
```

## Maintenance

### Updating Component Versions

All versions are centralized in `ansible/inventory.yaml` under the `unraid_k3d_clusters.vars` section:

```yaml
vars:
  k3d_version: "5.8.3"           # k3d binary version
  k3d_k3s_version: "v1.34.1-k3s1" # k3s/Kubernetes version
  kubectl_version: "1.34.0"      # kubectl binary version
  flux_version: "2.7.0"          # flux CLI version
```

### Updating k3d Binary

1. Update `k3d_version` in `ansible/inventory.yaml`
2. Re-run deployment playbook (downloads new binary):
   ```bash
   ansible-playbook -i ansible/inventory.yaml ansible/deploy-k3d-clusters.yaml
   ```
3. The new binary is downloaded to `/boot/bin/k3d` and copied to `/usr/local/bin/`

### Updating Kubernetes Version

k3d uses the k3s container image which includes Kubernetes. To update:

1. Update `k3d_k3s_version` in `ansible/inventory.yaml` (e.g., `v1.35.0-k3s1`)
2. Recreate the cluster (data persists in mounted volumes):
   ```bash
   # SSH to Unraid node
   ssh root@REDACTED_DOMAIN

   # Delete old cluster (containers only, not data)
   k3d cluster delete zapp-k3d

   # Recreate from config (uses new k3s version)
   k3d cluster create --config /mnt/user/appdata/k3d-zapp/config.yaml

   # Update Docker restart policies
   docker update --restart=unless-stopped k3d-zapp-k3d-server-0
   docker update --restart=unless-stopped k3d-zapp-k3d-serverlb
   ```
3. Re-bootstrap applications from your local machine:
   ```bash
   mise run bootstrap-apps zapp-k3d
   ```

**Note**: The k3d cluster config is rendered from `ansible/roles/k3d-unraid/templates/k3d-config.yaml.j2` which references `k3d_k3s_version`. After updating the inventory, you can re-run the Ansible playbook to update the config file, then recreate the cluster.

### Backup Strategy

- **Manifests**: Backed up in Git repository
- **Secrets**: Stored in 1Password
- **Persistent Data**: Backed up via Unraid array backup
- **Cluster State**: Can be recreated from Git + 1Password

### Disaster Recovery

To fully restore a k3d cluster from scratch:

**Scenario 1: Cluster deleted but Unraid data intact**
1. Ensure `/mnt/user/appdata/k3d-{cluster}/` directories still exist
2. SSH to Unraid and recreate cluster:
   ```bash
   k3d cluster create --config /mnt/user/appdata/k3d-zapp/config.yaml
   docker update --restart=unless-stopped k3d-zapp-k3d-server-0
   docker update --restart=unless-stopped k3d-zapp-k3d-serverlb
   ```
3. Re-bootstrap from local machine: `mise run bootstrap-apps zapp-k3d`
4. Flux will reconcile all applications from Git
5. Application data persists from volumes

**Scenario 2: Complete Unraid reinstall**
1. Restore `/boot/` from backup (contains binaries and configs)
2. Restore `/mnt/user/appdata/k3d-*/` from backup
3. Run Ansible deployment playbook: `ansible-playbook -i ansible/inventory.yaml ansible/deploy-k3d-clusters.yaml`
4. Setup kubeconfig: `ansible-playbook -i ansible/inventory.yaml ansible/setup-kubecontexts.yaml`
5. Re-bootstrap: `mise run bootstrap-apps zapp-k3d`
6. Verify Flux reconciliation: `flux get all -A --context k3d-zapp-k3d`

**Scenario 3: Lost all data, rebuild from Git + 1Password**
1. Fresh Unraid install with Docker enabled
2. Run Ansible deployment playbook (creates cluster from scratch)
3. Setup kubeconfig access
4. Bootstrap applications (pulls secrets from 1Password)
5. Flux reconciles all manifests from Git
6. Application data is lost (restore from backups if available)

## Next Steps

After successful bootstrap:

1. Deploy first application to test end-to-end workflow
2. Set up monitoring (Prometheus/Grafana) for k3d clusters
3. Configure ingress/gateway for application access
4. Migrate docker-compose workloads to Kubernetes
5. Set up backup automation for persistent volumes

## Implementation Summary

### Key Design Decisions

**Why Flannel CNI instead of Cilium?**
- Unraid uses a custom kernel that may not support all eBPF features required by Cilium
- Flannel (default k3s CNI) is lightweight and works reliably on Unraid
- For home k3d clusters, simplicity > advanced CNI features
- Traefik/Envoy Gateway can still be used for ingress without Cilium

**Why not disable Flannel like home-k3s?**
- The `--flannel-backend=none` flag in k3s disables the CNI entirely
- k3d cluster config does NOT include this flag (uses default `vxlan` mode)
- This ensures pods have networking from the start without manual CNI installation
- home-k3s uses Cilium for advanced features (BGP, L2 announcements, network policies)

**Why Ansible instead of manual scripts?**
- Idempotent operations (can re-run without breaking things)
- Handles Unraid's Slackware package management
- Manages binary downloads and persistence across reboots
- Centralizes configuration in `inventory.yaml`
- Separates concerns: cluster deployment vs. app bootstrap

**Why User Scripts plugin for auto-start?**
- Unraid's standard mechanism for running scripts at boot
- Runs after Docker is ready
- Easy to view logs via Unraid web UI
- Can manually trigger from UI for testing

### File Structure

```
home-ops/
├── ansible/
│   ├── inventory.yaml                    # Centralized config (versions, hosts, ports)
│   ├── deploy-k3d-clusters.yaml          # Main deployment playbook
│   ├── bootstrap-k3d-apps.yaml           # Application bootstrap playbook
│   ├── setup-kubecontexts.yaml           # Kubeconfig setup playbook
│   └── roles/k3d-unraid/
│       ├── tasks/main.yml                # Cluster deployment tasks
│       ├── templates/
│       │   ├── k3d-config.yaml.j2        # k3d cluster configuration
│       │   └── k3d-startup.sh.j2         # User Scripts startup script
│       ├── defaults/main.yml             # Default variables (versions)
│       └── handlers/main.yml             # Docker restart policy handler
├── bootstrap/
│   ├── zapp-k3d/
│   │   ├── helmfile.yaml                 # Core apps: CoreDNS, cert-manager, etc.
│   │   └── resources.yaml.j2             # Namespaces + secrets template
│   └── offsite-k3d/
│       ├── helmfile.yaml
│       └── resources.yaml.j2
└── kubernetes/
    ├── clusters/
    │   ├── zapp-k3d/
    │   │   └── apps/                     # Application manifests
    │   └── offsite-k3d/
    │       └── apps/
    └── flux/
        └── clusters/
            ├── zapp-k3d-ks.yaml          # Flux Kustomization for zapp-k3d
            └── offsite-k3d-ks.yaml       # Flux Kustomization for offsite-k3d
```

### Port Mapping Strategy

The k3d cluster exposes ports via the `k3d-{cluster}-serverlb` container:

```yaml
# In k3d-config.yaml.j2
ports:
  - port: 6443:6443         # Kubernetes API (for kubectl access)
  - port: 80:30080          # HTTP → NodePort 30080
  - port: 443:30443         # HTTPS → NodePort 30443
```

This means:
- Services should use NodePort 30080/30443 for HTTP/HTTPS
- Or use a LoadBalancer service with specific port annotations
- External access: `http://REDACTED_DOMAIN:80` → cluster's NodePort 30080

## Reference

- **Issue**: #297 (k3d cluster implementation)
- **Ansible Playbooks**:
  - `ansible/deploy-k3d-clusters.yaml` - Cluster deployment
  - `ansible/bootstrap-k3d-apps.yaml` - App bootstrap
  - `ansible/setup-kubecontexts.yaml` - Kubeconfig setup
- **Ansible Role**: `ansible/roles/k3d-unraid/`
- **Bootstrap**: `bootstrap/{zapp-k3d,offsite-k3d}/`
- **Cluster Configs**: `kubernetes/clusters/{zapp-k3d,offsite-k3d}/`
- **Flux Kustomizations**: `kubernetes/flux/clusters/{zapp-k3d,offsite-k3d}-ks.yaml`

## Support

For issues or questions:
1. Check this documentation
2. Review GitHub issue #297
3. Check Unraid forums for Unraid-specific issues
4. Review k3d documentation: https://k3d.io/
5. Review k3s documentation: https://docs.k3s.io/
