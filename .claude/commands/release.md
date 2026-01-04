---
description: Cut a new release (auto-bumps patch version, or specify version)
arguments:
  - name: version
    description: Version to release (e.g., 1.3.0). If omitted, auto-bumps patch.
    required: false
---

# Release RAMBar

Cut a new release for RAMBar. This will:
1. Determine the version (use provided version or auto-bump patch)
2. Create a git tag
3. Push the tag to trigger CI
4. CI automatically builds, creates GitHub release, and updates Homebrew tap

## Steps

1. Get the latest tag and determine the new version:
   - If version argument provided: use `v$arguments.version`
   - Otherwise: get latest tag, bump patch version

2. Create and push the tag:
   ```bash
   git tag <new_version>
   git push --tags
   ```

3. Report the release URL and optionally watch CI progress

## User provided version
$ARGUMENTS
