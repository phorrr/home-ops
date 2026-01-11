# Gateway External Auth Component

This component provides a reusable way for applications to configure Envoy Gateway external authentication with Authelia.

## Usage

Simply include the component in your application:

```yaml
components:
  - ../../../../components/gateway-ext-auth
```

That's it! The component automatically creates:
- **SecurityPolicy**: Configures Envoy Gateway external auth with Authelia
- **Auth Rules ConfigMap**: Defines access control rules for `${APP}.${GATEWAY_DOMAIN}` (defaults to `${APP}.${INTERNAL_DOMAIN}`)
- **Default Access**: Requires users in the `${APP}` group (or custom `${AUTHELIA_GROUP}`)
- **Two-factor Authentication**: Uses `two_factor` policy by default
- **Secure by Default**: Uses internal domain/gateway unless explicitly configured for external

## Features

- **Complete External Auth Setup**: Automatically configures both Envoy Gateway SecurityPolicy and Authelia rules
- **Dynamic Discovery**: ConfigMaps are automatically discovered by the auth-rules-watcher using the label `authelia.com/auth-rules: "true"`
- **Automatic ReferenceGrants**: The auth-rules-watcher automatically creates and manages ReferenceGrants for cross-namespace access
- **Real-time Updates**: Rules are applied within ~30 seconds of changes
- **Zero-trust Security**: Authelia uses `deny` as default policy
- **Automatic Reloads**: Stakater Reloader restarts Authelia when rules change
- **Plug-and-play**: Just include the component - no additional configuration needed

## Environment Variables

- `${APP}` - Application name (automatically set by most apps)
- `${DOMAIN}` - Your external domain (set globally)
- `${INTERNAL_DOMAIN}` - Your internal domain (set globally)
- `${GATEWAY_DOMAIN}` - The domain to use for auth rules (defaults to `${INTERNAL_DOMAIN}` for security)
- `${GATEWAY_NAME}` - The gateway to use (defaults to `internal` for security)
- `${AUTHELIA_GROUP}` - Group required for access (defaults to `${APP}`)
- `${AUTHELIA_POLICY}` - Authentication policy (defaults to `two_factor`)
- `${AUTHELIA_HTTPROUTE}` - HTTPRoute name to target (defaults to `${APP}`, use for app-template apps)
- `${AUTHELIA_SUBDOMAIN}` - Subdomain for auth rules (defaults to `${APP}`, use when app uses custom subdomain)

## Examples

**Default App** (internal domain by default):
```yaml
components:
  - ../../../../components/gateway-ext-auth
# Creates: myapp.${INTERNAL_DOMAIN} → requires group:myapp
```

**Custom Group** (using Flux substitution):
```yaml
# In kustomization.yaml
components:
  - ../../../../components/gateway-ext-auth

# In ks.yaml postBuild:
substitute:
  AUTHELIA_GROUP: arr-stack
# Creates: sonarr.${DOMAIN} → requires group:arr-stack
```

**Custom Policy**:
```yaml
# In ks.yaml postBuild:
substitute:
  AUTHELIA_POLICY: one_factor
# Uses single-factor authentication instead of two-factor
```

**External Domain** (for publicly accessible apps):
```yaml
# In ks.yaml postBuild:
substitute:
  GATEWAY_DOMAIN: ${DOMAIN}
  GATEWAY_NAME: external  # Also needed if your HelmRelease creates HTTPRoutes
# Creates: myapp.${DOMAIN} → requires authentication (publicly accessible)
```

**App-Template Apps** (with custom HTTPRoute names):
```yaml
# In ks.yaml postBuild:
substitute:
  AUTHELIA_HTTPROUTE: myapp-app  # Target the app-template generated HTTPRoute
# SecurityPolicy will target 'myapp-app' HTTPRoute instead of 'myapp'
```

Note: When creating HTTPRoutes in your HelmRelease, use these variables:
```yaml
# In helmrelease.yaml
route:
  app:
    hostnames: ["{{ .Release.Name }}.${GATEWAY_DOMAIN:-${INTERNAL_DOMAIN}}"]
    parentRefs:
      - name: ${GATEWAY_NAME:-internal}
        namespace: network
```

## Extending the Component

If you need additional functionality not provided by the environment variables, please extend the component itself rather than using patches. This maintains the plug-and-play philosophy and benefits all users.