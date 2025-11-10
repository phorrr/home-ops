# Home Operations - Kubernetes GitOps

Sanitized Kubernetes configurations from a home infrastructure setup shared for community reference.

**🚧 This repository is automatically synchronized from a private repository. Manual changes will be overwritten.**

## 📋 Overview

This repository contains Kubernetes manifests managed with GitOps principles using Flux CD. The configurations support:

- **Media Services**: Automated media management and streaming
- **Home Automation**: Smart home integrations
- **Monitoring & Observability**: Prometheus, Grafana, Loki
- **Authentication**: OAuth2 Proxy, Authelia
- **Storage**: Rook-Ceph distributed storage
- **Networking**: Cilium CNI with Gateway API

## 🏗️ Infrastructure

- **Cluster**: K3s on bare-metal nodes
- **GitOps**: Flux CD for automated reconciliation
- **Secrets**: 1Password External Secrets Operator
- **DNS**: CoreDNS with custom configurations
- **Ingress**: Gateway API with Cilium

## 📁 Repository Structure

```
kubernetes/
├── shared/              # Shared resources across clusters
│   ├── components/      # Reusable Kustomize components
│   └── repositories/    # Helm/OCI repository definitions
├── clusters/
│   └── home-k3s/        # Main production cluster
│       ├── apps/        # Application deployments
│       ├── config/      # Cluster-specific configuration
│       └── infrastructure/  # Core services
├── flux/                # Flux system components
└── bootstrap/           # Cluster initialization
```

## 🔒 Security & Privacy

This repository has been sanitized to remove:
- Personal identity information
- Private IP addresses (non-RFC1918)
- Domain names and hostnames
- Email addresses
- API keys and secrets
- Other sensitive configuration

The sanitization process uses:
1. **AI-powered analysis** (OpenRouter + GPT-4) for intelligent redaction
2. **Regex-based privacy gate** for additional safety checks

## 🤖 Automation

**Automatic Synchronization**: This repository is automatically updated when changes are pushed to the private source repository. The workflow:

1. Monitors private repository for changes
2. Performs AI-powered sanitization
3. Runs privacy gate checks
4. Publishes to this public repository (history-less)

## 📖 Learning Resources

This repository serves as a reference for:
- Flux CD GitOps patterns
- Kubernetes security best practices
- Home lab cluster management
- Application deployment patterns

## ⚠️ Disclaimer

**This repository is a reference implementation**. Configurations are specific to the source environment and may require adaptation for other clusters. Always:

- Review configurations before applying
- Adjust resource limits for your hardware
- Update domain/network settings
- Manage secrets securely (never commit plaintext secrets)

## 🙏 Acknowledgments

Inspired by and adapted from the excellent home operations repositories:
- [onedr0p/home-ops](https://github.com/onedr0p/home-ops)
- [bjw-s/home-ops](https://github.com/bjw-s/home-ops)
- [mchestr/homelab](https://github.com/mchestr/homelab)

## 📜 License

See [LICENSE](LICENSE) for details.

---

**Last Updated**: Automated on each sync
