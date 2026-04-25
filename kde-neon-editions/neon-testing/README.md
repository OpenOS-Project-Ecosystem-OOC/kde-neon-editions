# KDE Neon Testing Edition

Tracks upstream branch: `Neon/release` (pre-promotion staging) on [invent.kde.org/neon](https://invent.kde.org/neon)  
Archive: `http://archive.neon.kde.org/testing`

Packages land here before being promoted to the User Edition archive.
Includes extra QA tooling (apport, gdb, drkonqi).

## Pipeline

| Stage | Job | Trigger |
|---|---|---|
| sync | `sync-upstream` | Scheduled (nightly) |
| validate | `validate-manifest` | On manifest change or schedule |
| build-iso | `build-testing-iso` | Scheduled (nightly) or manual |
| test-iso | `smoke-test-iso` | After build (non-blocking) |
| publish | `publish-testing-iso` | After build + smoke test (scheduled only) |

## Manifest

Package list: [`manifests/testing.yaml`](manifests/testing.yaml)

## Local Build

```bash
export EDITION=testing
export NEON_ARCHIVE=http://archive.neon.kde.org/testing
export UBUNTU_SERIES=noble
export NEON_ARCHIVE_KEY=45F4C354638D1F29
bash scripts/build-iso.sh
```
