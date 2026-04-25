# KDE Neon Developer Edition (Unstable)

Tracks upstream branch: `Neon/unstable` on [invent.kde.org/neon](https://invent.kde.org/neon)  
Archive: `http://archive.neon.kde.org/dev/unstable`

Built from KDE master branch (git HEAD). **May be broken at any time.**
Not for production use. Includes debug symbols and full developer toolchain.

## Pipeline

| Stage | Job | Trigger |
|---|---|---|
| sync | `sync-upstream` | Scheduled (nightly) |
| validate | `validate-manifest` | On manifest change or schedule |
| build-iso | `build-developer-unstable-iso` | Scheduled (nightly) — `allow_failure: true` |
| publish | `publish-developer-unstable-iso` | After build, even if partial |

Build failures are expected and do not block other edition pipelines.

## Manifest

Package list: [`manifests/developer-unstable.yaml`](manifests/developer-unstable.yaml)

## Local Build

```bash
export EDITION=developer-unstable
export NEON_ARCHIVE=http://archive.neon.kde.org/dev/unstable
export UBUNTU_SERIES=noble
export NEON_ARCHIVE_KEY=45F4C354638D1F29
bash scripts/build-iso.sh
```
