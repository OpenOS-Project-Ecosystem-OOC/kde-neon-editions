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

### 2. Configure upstream sync schedules

Each edition repo has a scheduled pipeline that runs `sync-upstream.sh` every
30 minutes to pull the latest commits from `kde-groups/neon` into a tracking
branch. Schedules are created via:

```bash
export GITLAB_TOKEN="<your-api-token>"
export GITLAB_GROUP="openos-project/kde-ecosystem-deving/neon-deving"
bash ci-templates/scripts/setup-mirror.sh
```

To trigger an immediate sync without waiting for the schedule:

```bash
bash ci-templates/scripts/trigger-mirror-sync.sh
```

> **Note:** GitLab pull mirroring (the built-in mirror feature) requires
> GitLab Premium. The CI-based sync approach works on the free tier.

### 3. Set CI/CD variables

Set these at the **group level** (`neon-deving` → Settings → CI/CD → Variables)
so all edition repos inherit them:

| Variable | Value | Masked | Protected |
|---|---|---|---|
| `GITLAB_TOKEN` | Personal access token (api + write_repository + write_packages) | ✅ | ✅ |

Set these **per project** (or override at group level) when ready:

| Variable | Value | Notes |
|---|---|---|
| `GPG_SIGNING_KEY` | GPG key fingerprint | ISO signing — optional, skipped if unset |
| `GPG_PRIVATE_KEY` | Armored private key (`gpg --armor --export-secret-keys`) | File type, protected |
| `PUBLISH_TARGET` | `gitlab-packages` (default) or `rsync` | Already set to `gitlab-packages` |
| `RSYNC_HOST` | Destination host | Only needed for rsync publishing |
| `RSYNC_PATH` | Destination path on host | Only needed for rsync publishing |
| `SSH_PRIVATE_KEY` | SSH private key for rsync | File type, only needed for rsync |

### 4. Register a privileged runner

ISO builds require `live-build` with loop devices — must run on a VM runner,
not a container. Two options:

- **garm-gitlab (recommended):** auto-scaling Incus VMs. See `deploy/RUNNER-SETUP.md`.
- **Static runner:** single dedicated build machine. See `deploy/RUNNER-SETUP.md`.

### 5. Schedule nightly builds

Already configured: `0 2 * * *` UTC on the root `kde-neon-editions` repo.

To add or modify: CI/CD → Schedules in the root repo.

## Upstream Relationship

This project does **not** fork or replace upstream KDE Neon. It mirrors
upstream packaging and builds ISOs using the same archives. Changes to
KDE packages must be contributed upstream to
[invent.kde.org/neon](https://invent.kde.org/neon).
