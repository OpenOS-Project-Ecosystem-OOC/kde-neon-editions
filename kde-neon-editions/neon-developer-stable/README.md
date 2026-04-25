# KDE Neon Developer Edition (Stable)

Tracks upstream branch: `Neon/stable` on [invent.kde.org/neon](https://invent.kde.org/neon)  
Archive: `http://archive.neon.kde.org/dev/stable`

Built from KDE stable and beta branch tarballs. Includes a full developer
toolchain (cmake, clang, kdevelop, debhelper, etc.).

## Pipeline

| Stage | Job | Trigger |
|---|---|---|
| sync | `sync-upstream` | Scheduled (nightly) |
| validate | `validate-manifest` | On manifest change or schedule |
| build-iso | `build-developer-stable-iso` | Scheduled (nightly) or manual |
| publish | `publish-developer-stable-iso` | After successful build (scheduled only) |

## Manifest

Package list: [`manifests/developer-stable.yaml`](manifests/developer-stable.yaml)

## Local Build

```bash
export EDITION=developer-stable
export NEON_ARCHIVE=http://archive.neon.kde.org/dev/stable
export UBUNTU_SERIES=noble
export NEON_ARCHIVE_KEY=45F4C354638D1F29
bash scripts/build-iso.sh
```
