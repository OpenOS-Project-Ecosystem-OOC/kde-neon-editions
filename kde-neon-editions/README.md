# KDE Neon Editions — OpenOS Project

Separate GitLab repos and CI/CD pipelines for each KDE Neon edition,
tracking upstream [invent.kde.org/neon](https://invent.kde.org/neon).

## Repos

| Repo | Edition | Upstream Branch | Archive |
|---|---|---|---|
| [neon-user](./neon-user/) | User Edition | `Neon/release` | `archive.neon.kde.org/user` |
| [neon-testing](./neon-testing/) | Testing Edition | `Neon/release` (staging) | `archive.neon.kde.org/testing` |
| [neon-developer-stable](./neon-developer-stable/) | Developer Edition (Stable) | `Neon/stable` | `archive.neon.kde.org/dev/stable` |
| [neon-developer-unstable](./neon-developer-unstable/) | Developer Edition (Unstable) | `Neon/unstable` | `archive.neon.kde.org/dev/unstable` |
| [ci-templates](./ci-templates/) | Shared CI templates | — | — |

## How It Works

```
invent.kde.org/neon          GitLab (this group)
─────────────────────        ──────────────────────────────────────
Neon/release  ──────────────► neon-user        → ISO build → publish
Neon/release  ──────────────► neon-testing     → ISO build → smoke test → publish
Neon/stable   ──────────────► neon-developer-stable  → ISO build → publish
Neon/unstable ──────────────► neon-developer-unstable → ISO build (allow_failure) → publish
```

Upstream mirroring runs on a schedule (every 30 min via GitLab pull mirroring).
ISO builds run nightly via a scheduled pipeline on this root repo.

## Pipelines

- **Root pipeline** (`.gitlab-ci.yml` here): triggers all four edition builds in parallel.
- **Per-edition pipelines**: each repo has its own `.gitlab-ci.yml` for isolated builds.
- **Shared templates** (`ci-templates/`): included by all edition pipelines via `include:`.

## First-Time Setup

### 1. Create the repos on GitLab

Create four projects under your group:
- `neon-user`
- `neon-testing`
- `neon-developer-stable`
- `neon-developer-unstable`
- `ci-templates`

### 2. Configure upstream pull mirroring

```bash
export GITLAB_TOKEN="<your-api-token>"
export GITLAB_GROUP="openos-project/kde-ecosystem-deving/kde-groups/neon"
bash ci-templates/scripts/setup-mirror.sh
```

### 3. Set CI/CD variables

In each project (Settings → CI/CD → Variables):

| Variable | Value | Masked |
|---|---|---|
| `GITLAB_TOKEN` | Project access token (write_repository + write_packages) | ✅ |
| `GPG_SIGNING_KEY` | Fingerprint of your ISO signing key | No |
| `GPG_PRIVATE_KEY` | Armored private key export | ✅ (file type) |

For rsync publishing, also set:
- `RSYNC_HOST`, `RSYNC_PATH`, `SSH_PRIVATE_KEY`

### 4. Register a privileged runner

ISO builds require `live-build` which needs loop devices and chroot.

```toml
# /etc/gitlab-runner/config.toml
[[runners]]
  name = "neon-iso-builder"
  executor = "docker"
  [runners.docker]
    image = "ubuntu:noble"
    privileged = true
    volumes = ["/cache", "/dev:/dev"]
```

Tag the runner `privileged` and add that tag to your runner registration.

### 5. Schedule nightly builds

In the root repo: CI/CD → Schedules → New schedule
- Interval: `0 2 * * *` (02:00 UTC nightly)
- Target branch: `main`

## Upstream Relationship

This project does **not** fork or replace upstream KDE Neon. It mirrors
upstream packaging and builds ISOs using the same archives. Changes to
KDE packages must be contributed upstream to
[invent.kde.org/neon](https://invent.kde.org/neon).
