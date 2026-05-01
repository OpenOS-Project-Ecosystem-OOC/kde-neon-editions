# ISO Builder Runner Setup

ISO builds use `live-build`, which requires loop devices and chroot. This
means builds must run inside a VM (not a container). The recommended approach
is the `garm-gitlab` runner manager, which provisions Incus VMs on demand.

## Option A — garm-gitlab (recommended)

`garm-gitlab` manages a pool of Incus VMs that register as GitLab runners,
run one job each, then are destroyed. This gives clean build environments
and automatic scaling.

### Prerequisites

- An Incus host with KVM support (`incus info | grep -i kvm`)
- `garm-gitlab` installed and configured (see `ci/runners/garm-gitlab/deploy/SETUP.md`
  in the `gitlab-enhanced` repo)
- Ubuntu Noble base image in Incus: `incus image copy images:ubuntu/24.04 local:`

### 1. Create the Incus profile

```bash
incus profile create iso-builder
incus profile edit iso-builder < deploy/incus-profile-iso-builder.yaml
```

Verify:

```bash
incus profile show iso-builder
```

### 2. Register the pool with garm-gitlab

```bash
export GARM_GITLAB_TOKEN="<your-gitlab-token>"
export GARM_GITLAB_GROUP="openos-project/kde-ecosystem-deving/neon-deving"

garm-gitlab pool create --config deploy/garm-pool-iso-builder.yaml
```

This creates a pool named `neon-iso-builders` that:
- Keeps 1 warm VM idle (fast job start)
- Scales up to 4 concurrent VMs
- Tags runners `privileged` + `iso-builder` + `neon`
- Destroys each VM after its job completes

### 3. Verify runners appear in GitLab

```
https://gitlab.com/groups/openos-project/kde-ecosystem-deving/neon-deving/-/runners
```

You should see runners with tags `privileged, iso-builder, neon` come online
within ~2 minutes of the pool starting.

---

## Option B — Static self-hosted runner (simpler, no auto-scaling)

If you have a single dedicated build machine and don't need auto-scaling,
register a runner directly.

### Prerequisites

- Ubuntu Noble host with KVM
- `gitlab-runner` installed: https://docs.gitlab.com/runner/install/linux-repository.html
- Sufficient disk: 40 GB free per concurrent build

### 1. Install live-build dependencies

```bash
apt-get install -y \
  live-build ubuntu-defaults-builder debootstrap squashfs-tools \
  xorriso isolinux syslinux-common grub-efi-amd64-bin grub-pc-bin \
  mtools dosfstools rsync wget curl gpg ca-certificates python3 python3-yaml git
```

### 2. Register the runner

```bash
gitlab-runner register \
  --non-interactive \
  --url "https://gitlab.com" \
  --token "<group-runner-token>" \
  --executor "shell" \
  --description "neon-iso-builder-static" \
  --tag-list "privileged,iso-builder,neon" \
  --run-untagged false \
  --locked false
```

Get the group runner token from:
`https://gitlab.com/groups/openos-project/kde-ecosystem-deving/neon-deving/-/runners/new`

### 3. Configure concurrent builds

Edit `/etc/gitlab-runner/config.toml`:

```toml
concurrent = 2   # adjust to available disk/CPU

[[runners]]
  name = "neon-iso-builder-static"
  executor = "shell"
  # shell executor runs as gitlab-runner user — ensure it has sudo for live-build
```

Grant `live-build` sudo access without password:

```bash
echo "gitlab-runner ALL=(ALL) NOPASSWD: /usr/bin/lb, /usr/sbin/debootstrap" \
  >> /etc/sudoers.d/gitlab-runner-lb
chmod 440 /etc/sudoers.d/gitlab-runner-lb
```

---

## Verifying a build

Once a runner is online, trigger a manual build from any edition repo:

```
https://gitlab.com/openos-project/kde-ecosystem-deving/neon-deving/neon-user/-/pipelines/new
```

Set `CI_PIPELINE_SOURCE=web` and run the `build-user-iso` job manually.
The job will take 20–40 minutes and produce a `.iso` + `.iso.sha256` artifact.
