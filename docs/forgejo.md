# Forgejo Administration

Commands to be run inside the Forgejo pod:

```bash
kubectl exec -it -n forgejo deploy/forgejo -- sh
```

## Creating Access Tokens

Generate an access token for an existing user:

```bash
forgejo admin user generate-access-token \
  --username mybot \
  --token-name cicd-token \
  --scopes "write:repository,write:package" \
  --raw
```

## Creating Service Accounts

Create a service account with an access token in one command:

```bash
forgejo admin user create \
  --username registry-bot \
  --email bot@example.com \
  --random-password \
  --access-token \
  --access-token-name "registry-push" \
  --access-token-scopes "write:package"
```

## Common Token Scopes

- `read:repository` - Read access to repositories
- `write:repository` - Write access to repositories
- `read:package` - Read access to packages/container registry
- `write:package` - Push to packages/container registry
- `read:user` - Read user information
- `write:user` - Modify user settings
- `read:organization` - Read organization info
- `write:organization` - Manage organizations
- `read:activitypub` - ActivityPub read access
- `write:activitypub` - ActivityPub write access
- `read:issue` / `write:issue` - Issue management

## Renovate Bot Infrastructure

### Creating the Bot User

```bash
kubectl exec -it -n forgejo deploy/forgejo -- \
  forgejo admin user create \
    --username renovate-bot \
    --email renovate@REDACTED_DOMAIN \
    --random-password \
    --must-change-password=false
```

### Generating the API Token

Required scopes: `write:repository`, `read:user`, `write:issue`, `read:organization`

```bash
kubectl exec -it -n forgejo deploy/forgejo -- \
  forgejo admin user generate-access-token \
    --username renovate-bot \
    --token-name renovate \
    --scopes "write:repository,read:user,write:issue,read:organization" \
    --raw
```

### 1Password Setup

Create item `renovate` with field `token` containing the generated token.

### Controlling Access

Renovate autodiscovers all repositories the bot can access. Control scope by:

1. **Organization teams**: Add `renovate-bot` to teams with repo access
2. **Direct collaboration**: Add `renovate-bot` to specific repos

To limit discovery, add `autodiscoverFilter` to `kubernetes/clusters/home-k3s/apps/forgejo/renovate/app/configmap.yaml`:

```json
{
  "autodiscoverFilter": ["ops/*", "myorg/*"]
}
```
