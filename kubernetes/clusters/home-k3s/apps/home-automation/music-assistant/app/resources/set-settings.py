#!/usr/bin/env python3
"""
Music Assistant settings initializer.
Sets base_url and published_ip from environment variables.
"""
import json
import os

settings_file = "/data/settings.json"
base_url = os.environ.get("BASE_URL")
published_ip = os.environ.get("PUBLISHED_IP")

if os.path.exists(settings_file):
    with open(settings_file, 'r') as f:
        settings = json.load(f)

    if 'core' not in settings:
        settings['core'] = {}

    # base_url in core.webserver.values
    if 'webserver' not in settings['core']:
        settings['core']['webserver'] = {'values': {}, 'domain': 'webserver'}
    if 'values' not in settings['core']['webserver']:
        settings['core']['webserver']['values'] = {}
    settings['core']['webserver']['values']['base_url'] = base_url

    # published_ip in core.streamserver.values
    if 'streamserver' not in settings['core']:
        settings['core']['streamserver'] = {'values': {}, 'domain': 'streamserver'}
    if 'values' not in settings['core']['streamserver']:
        settings['core']['streamserver']['values'] = {}
    settings['core']['streamserver']['values']['published_ip'] = published_ip

    with open(settings_file, 'w') as f:
        json.dump(settings, f, indent=2)

    print(f"Updated base_url to {base_url}, published_ip to {published_ip}")
else:
    print("Settings file not found, will be created on first run")
