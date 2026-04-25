# ci-templates

Shared GitLab CI template files for all KDE Neon edition repos.

## Files

| File | Purpose |
|---|---|
| `iso-build.yml` | Base job definitions for building and publishing ISOs |
| `mirror-sync.yml` | Base job for syncing from upstream `invent.kde.org/neon` |
| `manifest-validate.yml` | Base job for validating edition package manifests |

## Usage

In any edition repo's `.gitlab-ci.yml`:

```yaml
include:
  - project: 'openos-project/kde-ecosystem-deving/kde-groups/neon/ci-templates'
    ref: main
    file:
      - '/iso-build.yml'
      - '/mirror-sync.yml'
      - '/manifest-validate.yml'
```

Then extend the base jobs:

```yaml
build-iso:
  extends: .iso-build-base
  variables:
    EDITION: user
    NEON_BRANCH: Neon/release
    UBUNTU_SERIES: noble
    NEON_ARCHIVE: "http://archive.neon.kde.org/user"
```

## Runner Requirements

ISO builds require a GitLab runner with:
- `privileged: true` (live-build needs loop devices and chroot)
- At least 20 GB free disk space
- Tag: `privileged`

Register a runner with:

```toml
[[runners]]
  executor = "docker"
  [runners.docker]
    privileged = true
    volumes = ["/cache", "/dev:/dev"]
```
