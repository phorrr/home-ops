# Using Renovate

Renovate automatically creates pull requests to keep your dependencies up to date.

## Enabling Renovate for Your Repository

1. Ask an admin to add `renovate-bot` as a collaborator with Write access
2. Renovate will create an onboarding PR with a default config
3. Merge the PR to enable automated dependency updates

## Configuration

After onboarding, you'll have a `renovate.json` in your repo. Customize it as needed:

### Minimal Config

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended"]
}
```

### Common Options

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended"],
  "timezone": "UTC",
  "schedule": ["before 7am on Monday"],
  "labels": ["dependencies"],
  "automerge": true,
  "automergeType": "pr",
  "platformAutomerge": true
}
```

### Grouping Updates

```json
{
  "packageRules": [
    {
      "groupName": "all minor and patch",
      "matchUpdateTypes": ["minor", "patch"],
      "automerge": true
    }
  ]
}
```

### Ignoring Dependencies

```json
{
  "ignoreDeps": ["some-package"],
  "packageRules": [
    {
      "matchPackageNames": ["legacy-*"],
      "enabled": false
    }
  ]
}
```

## Schedule

Renovate runs hourly. PRs are created when updates are detected.

## More Information

- [Renovate Documentation](https://docs.renovatebot.com/)
- [Configuration Options](https://docs.renovatebot.com/configuration-options/)
