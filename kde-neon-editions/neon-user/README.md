# KDE Neon User Edition

Tracks upstream branch: `Neon/release` on [invent.kde.org/neon](https://invent.kde.org/neon)  
Archive: `http://archive.neon.kde.org/user`

Built from KDE stable release tarballs. This is the edition recommended for
general use.

## Pipeline

| Stage | Job | Trigger |
|---|---|---|
| sync | `sync-upstream` | Scheduled (nightly) |
| validate | `validate-manifest` | On manifest change or schedule |
| build-iso | `build-user-iso` | Scheduled (nightly) or manual |
| publish | `publish-user-iso` | After successful build (scheduled only) |

## Manifest

Package list: [`manifests/user.yaml`](manifests/user.yaml)

Edit this file to add or remove packages from the ISO. The manifest is
validated before every build.

## Local Build

```bash
# Requires: live-build, ubuntu-defaults-builder, debootstrap
export EDITION=user
export NEON_ARCHIVE=http://archive.neon.kde.org/user
export UBUNTU_SERIES=noble
export NEON_ARCHIVE_KEY=45F4C354638D1F29
bash scripts/build-iso.sh
```
