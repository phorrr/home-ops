#!/usr/bin/env python
"""
Update Authelia auth rules ConfigMap from discovered ConfigMaps.
This script runs in a separate deployment and updates a ConfigMap that Authelia loads.
"""

import os
import sys
import yaml
import base64
from pathlib import Path

def get_k8s_token():
    """Get the service account token"""
    with open('/var/run/secrets/kubernetes.io/serviceaccount/token', 'r') as f:
        return f.read().strip()

def get_k8s_ca_cert():
    """Get the CA certificate"""
    with open('/var/run/secrets/kubernetes.io/serviceaccount/ca.crt', 'r') as f:
        return f.read()

def k8s_api_call(method, url, data=None):
    """Make a direct API call to Kubernetes"""
    import urllib.request
    import urllib.parse
    import json
    import ssl
    
    # Get service account credentials
    token = get_k8s_token()
    
    # Create SSL context with CA cert
    context = ssl.create_default_context()
    ca_cert_path = '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt'
    context.load_verify_locations(ca_cert_path)
    
    # Full URL
    k8s_host = os.environ.get('KUBERNETES_SERVICE_HOST')
    k8s_port = os.environ.get('KUBERNETES_SERVICE_PORT')
    full_url = f"https://{k8s_host}:{k8s_port}{url}"
    
    # Create request
    req = urllib.request.Request(full_url, method=method)
    req.add_header('Authorization', f'Bearer {token}')
    req.add_header('Content-Type', 'application/json')
    
    if data:
        req.data = json.dumps(data).encode('utf-8')
    
    try:
        with urllib.request.urlopen(req, context=context) as response:
            if response.status == 200:
                return json.loads(response.read().decode('utf-8'))
            else:
                return None
    except Exception as e:
        print(f"K8s API call failed: {e}")
        return None

def update_reference_grant(namespaces_set):
    """Update or create ReferenceGrant for SecurityPolicies to access Authelia"""
    print(f"=== Updating ReferenceGrant for namespaces: {namespaces_set} ===")
    
    namespace = "auth"
    referencegrant_name = "allow-securitypolicies-to-authelia"
    
    # Build the from entries for each namespace
    from_entries = []
    for ns in sorted(namespaces_set):
        if ns != namespace:  # Skip auth namespace itself
            from_entries.append({
                "group": "gateway.envoyproxy.io",
                "kind": "SecurityPolicy",
                "namespace": ns
            })
    
    if not from_entries:
        print("No external namespaces need ReferenceGrant")
        # Check if ReferenceGrant exists and delete it if no longer needed
        current_rg = k8s_api_call("GET", f"/apis/gateway.networking.k8s.io/v1beta1/namespaces/{namespace}/referencegrants/{referencegrant_name}")
        if current_rg and current_rg.get('metadata', {}).get('labels', {}).get('app.kubernetes.io/managed-by') == 'authelia-auth-rules-watcher':
            # Delete the ReferenceGrant since it's no longer needed
            result = k8s_api_call("DELETE", f"/apis/gateway.networking.k8s.io/v1beta1/namespaces/{namespace}/referencegrants/{referencegrant_name}")
            if result:
                print(f"Successfully deleted ReferenceGrant (no longer needed)")
            else:
                print(f"Failed to delete ReferenceGrant")
        return
    
    # Create ReferenceGrant data
    referencegrant_data = {
        "apiVersion": "gateway.networking.k8s.io/v1beta1",
        "kind": "ReferenceGrant",
        "metadata": {
            "name": referencegrant_name,
            "namespace": namespace,
            "labels": {
                "app.kubernetes.io/managed-by": "authelia-auth-rules-watcher"
            }
        },
        "spec": {
            "from": from_entries,
            "to": [{
                "group": "",
                "kind": "Service",
                "name": "authelia"
            }]
        }
    }
    
    # Check if ReferenceGrant exists
    current_rg = k8s_api_call("GET", f"/apis/gateway.networking.k8s.io/v1beta1/namespaces/{namespace}/referencegrants/{referencegrant_name}")
    
    # Check if update is needed
    needs_update = False
    if current_rg:
        # Check if it's managed by us
        if current_rg.get('metadata', {}).get('labels', {}).get('app.kubernetes.io/managed-by') != 'authelia-auth-rules-watcher':
            print(f"WARNING: ReferenceGrant exists but is not managed by auth-rules-watcher, skipping update")
            return
        
        # Compare current namespaces with desired
        current_from = current_rg.get('spec', {}).get('from', [])
        current_namespaces = set()
        for entry in current_from:
            if entry.get('group') == 'gateway.envoyproxy.io' and entry.get('kind') == 'SecurityPolicy':
                current_namespaces.add(entry.get('namespace'))
        
        desired_namespaces = set(ns for ns in namespaces_set if ns != namespace)
        
        if current_namespaces != desired_namespaces:
            needs_update = True
            print(f"ReferenceGrant needs update: current namespaces {current_namespaces} != desired {desired_namespaces}")
        else:
            print(f"ReferenceGrant is already up to date with namespaces: {current_namespaces}")
            return
    
    if current_rg and needs_update:
        # Update existing ReferenceGrant - need to include resourceVersion
        referencegrant_data['metadata']['resourceVersion'] = current_rg['metadata']['resourceVersion']
        result = k8s_api_call("PUT", f"/apis/gateway.networking.k8s.io/v1beta1/namespaces/{namespace}/referencegrants/{referencegrant_name}", referencegrant_data)
        action = "updated"
    elif not current_rg:
        # Create new ReferenceGrant
        result = k8s_api_call("POST", f"/apis/gateway.networking.k8s.io/v1beta1/namespaces/{namespace}/referencegrants", referencegrant_data)
        action = "created"
    else:
        return  # No update needed
    
    if result:
        print(f"Successfully {action} ReferenceGrant for {len(from_entries)} namespaces")
    else:
        print(f"Failed to {action} ReferenceGrant")

def main():
    print("=== Starting auth rules ConfigMap and ReferenceGrant updater ===")
    
    # Configuration
    auth_rules_dir = Path("/tmp/auth-rules")
    configmap_name = "authelia-auth-rules"
    namespace = "auth"
    
    print(f"Checking for auth-rules in: {auth_rules_dir}")
    
    # Collect all auth rules and track namespaces
    all_rules = []
    namespaces_with_rules = set()
    
    if auth_rules_dir.exists():
        for rules_file in auth_rules_dir.glob("*.yaml"):
            if rules_file.is_file():
                print(f"Processing rules file: {rules_file}")
                
                # Extract namespace from filename
                # k8s-sidecar with UNIQUE_FILENAMES=true creates files like: namespace_<namespace>.configmap_<name>.rules.yaml
                filename = rules_file.stem  # e.g., "namespace_media.configmap_sonarr-auth-rules.rules"
                if filename.startswith('namespace_'):
                    # Split on '.configmap_' to get the namespace part
                    namespace_part = filename.split('.configmap_')[0]
                    # Remove the 'namespace_' prefix
                    file_namespace = namespace_part.replace('namespace_', '')
                    if file_namespace:
                        namespaces_with_rules.add(file_namespace)
                        print(f"Detected namespace: {file_namespace}")
                
                try:
                    with open(rules_file, 'r') as f:
                        content = f.read().strip()
                    
                    if content:
                        # Parse the YAML to validate it
                        rules_data = yaml.safe_load(content)
                        
                        if rules_data:
                            # Handle both single rule and list of rules
                            if isinstance(rules_data, list):
                                all_rules.extend(rules_data)
                            elif isinstance(rules_data, dict):
                                all_rules.append(rules_data)
                            
                            print(f"Added {len(rules_data) if isinstance(rules_data, list) else 1} rules from {rules_file}")
                        
                except yaml.YAMLError as e:
                    print(f"WARNING: Skipping invalid YAML file {rules_file}: {e}")
                    continue
                except Exception as e:
                    print(f"WARNING: Failed to process {rules_file}: {e}")
                    continue
    
    # Create the configuration for Authelia
    if all_rules:
        auth_config = {
            'access_control': {
                'rules': all_rules
            }
        }
        print(f"Creating ConfigMap with {len(all_rules)} total rules")
    else:
        # Create empty rules to ensure valid configuration
        auth_config = {
            'access_control': {
                'rules': []
            }
        }
        print("No rules found, creating empty rules ConfigMap")
    
    # Convert to YAML
    config_yaml = yaml.dump(auth_config, default_flow_style=False, allow_unicode=True)
    
    # Check if ConfigMap exists and get current content
    current_configmap = k8s_api_call("GET", f"/api/v1/namespaces/{namespace}/configmaps/{configmap_name}")
    
    current_config = None
    if current_configmap and 'data' in current_configmap and 'rules.yaml' in current_configmap['data']:
        current_config = current_configmap['data']['rules.yaml']
    
    if current_config == config_yaml:
        print("ConfigMap is already up to date, no changes needed")
        # Still update ReferenceGrant in case namespaces changed
        if namespaces_with_rules:
            update_reference_grant(namespaces_with_rules)
        return
    
    print("ConfigMap content has changed, updating...")
    
    # Create or update the ConfigMap
    configmap_data = {
        "apiVersion": "v1",
        "kind": "ConfigMap",
        "metadata": {
            "name": configmap_name,
            "namespace": namespace
        },
        "data": {
            "rules.yaml": config_yaml
        }
    }
    
    if current_configmap:
        # ConfigMap exists, update it
        result = k8s_api_call("PUT", f"/api/v1/namespaces/{namespace}/configmaps/{configmap_name}", configmap_data)
    else:
        # ConfigMap should always exist (created by Flux), but if not, try to patch it
        print("WARNING: ConfigMap doesn't exist, this shouldn't happen with Flux-managed ConfigMap")
        result = k8s_api_call("PUT", f"/api/v1/namespaces/{namespace}/configmaps/{configmap_name}", configmap_data)
    
    if result:
        print(f"Successfully updated ConfigMap {configmap_name}")
    else:
        print(f"Failed to update ConfigMap {configmap_name}")
        sys.exit(1)
    
    # Update ReferenceGrant for discovered namespaces
    if namespaces_with_rules:
        update_reference_grant(namespaces_with_rules)
    
    print("=== Auth rules ConfigMap and ReferenceGrant update complete ===")

if __name__ == "__main__":
    main()