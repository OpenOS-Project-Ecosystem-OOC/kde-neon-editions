#!/usr/bin/env sh
# register-runner.sh — plug-and-play ISO builder runner setup.
#
# Detects the OS, installs gitlab-runner and live-build dependencies,
# then registers the machine as a GitLab runner with the correct tags.
#
# Supports: Ubuntu/Debian, Fedora/RHEL/CentOS, Arch Linux, macOS (partial).
# Requires: x86_64 or arm64, KVM or loop-device access, sudo/root.
#
# Usage (one-liner from any machine):
#
#   curl -fsSL \
#     https://gitlab.com/openos-project/kde-ecosystem-deving/neon-deving/kde-neon-editions/-/raw/main/deploy/register-runner.sh \
#     | GITLAB_RUNNER_TOKEN="<token>" sh
#
# Or clone the repo and run locally:
#
#   GITLAB_RUNNER_TOKEN="<token>" bash deploy/register-runner.sh
#
# Required environment variables:
#   GITLAB_RUNNER_TOKEN   — group runner authentication token
#                           Get it from:
#                           https://gitlab.com/groups/openos-project/kde-ecosystem-deving/neon-deving/-/runners/new
#
# Optional environment variables:
#   GITLAB_URL            — defaults to https://gitlab.com
#   RUNNER_NAME           — defaults to hostname
#   RUNNER_CONCURRENT     — number of concurrent builds (default: 1)
#   RUNNER_TAGS           — comma-separated tags (default: privileged,iso-builder,neon)
#   SKIP_DEPS             — set to 1 to skip package installation (deps already present)
#   SKIP_REGISTER         — set to 1 to only install deps, skip runner registration

set -e

GITLAB_URL="${GITLAB_URL:-https://gitlab.com}"
RUNNER_NAME="${RUNNER_NAME:-$(hostname)-iso-builder}"
RUNNER_CONCURRENT="${RUNNER_CONCURRENT:-1}"
RUNNER_TAGS="${RUNNER_TAGS:-privileged,iso-builder,neon}"
SKIP_DEPS="${SKIP_DEPS:-0}"
SKIP_REGISTER="${SKIP_REGISTER:-0}"

# ── Helpers ───────────────────────────────────────────────────────────────────

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
      SUDO="sudo"
    else
      die "Must run as root or with sudo available"
    fi
  else
    SUDO=""
  fi
}

# ── OS detection ──────────────────────────────────────────────────────────────

detect_os() {
  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID}"
    OS_ID_LIKE="${ID_LIKE:-}"
    OS_VERSION="${VERSION_ID:-}"
  elif command -v sw_vers >/dev/null 2>&1; then
    OS_ID="macos"
    OS_VERSION=$(sw_vers -productVersion)
  else
    die "Cannot detect OS. Set SKIP_DEPS=1 and install dependencies manually."
  fi

  ARCH=$(uname -m)
  case "${ARCH}" in
    x86_64)  ARCH_LABEL="amd64" ;;
    aarch64|arm64) ARCH_LABEL="arm64" ;;
    *) die "Unsupported architecture: ${ARCH}" ;;
  esac

  log "Detected OS: ${OS_ID} ${OS_VERSION} (${ARCH})"
}

# ── Prerequisite checks ───────────────────────────────────────────────────────

check_prerequisites() {
  log "Checking prerequisites"

  # KVM
  if [ -e /dev/kvm ]; then
    ok "/dev/kvm present — KVM acceleration available"
  else
    warn "/dev/kvm not found — live-build will be slower (software emulation)"
    warn "On a VM: ensure nested virtualisation or KVM passthrough is enabled"
  fi

  # Loop devices
  if losetup -f >/dev/null 2>&1; then
    ok "Loop devices available"
  else
    warn "Loop devices not available — live-build chroot may fail"
    warn "On a container: switch to a VM or bare-metal host"
  fi

  # Disk space (need at least 40 GB free)
  FREE_KB=$(df -k . | awk 'NR==2{print $4}')
  FREE_GB=$((FREE_KB / 1024 / 1024))
  if [ "${FREE_GB}" -ge 40 ]; then
    ok "${FREE_GB} GB free disk space"
  else
    warn "Only ${FREE_GB} GB free — recommend at least 40 GB per concurrent build"
  fi

  # RAM (need at least 6 GB)
  if command -v free >/dev/null 2>&1; then
    FREE_MB=$(free -m | awk '/^Mem:/{print $2}')
    if [ "${FREE_MB}" -ge 6144 ]; then
      ok "${FREE_MB} MB RAM"
    else
      warn "Only ${FREE_MB} MB RAM — recommend at least 8 GB"
    fi
  fi
}

# ── Package installation ──────────────────────────────────────────────────────

install_deps_debian() {
  log "Installing dependencies (apt)"
  $SUDO apt-get update -qq
  $SUDO apt-get install -y --no-install-recommends \
    curl wget gnupg ca-certificates \
    live-build ubuntu-defaults-builder debootstrap \
    squashfs-tools xorriso isolinux syslinux-common \
    grub-efi-amd64-bin grub-pc-bin mtools dosfstools \
    rsync gpg python3 python3-yaml git
  ok "apt dependencies installed"
}

install_deps_fedora() {
  log "Installing dependencies (dnf)"
  $SUDO dnf install -y \
    curl wget gnupg2 ca-certificates \
    debootstrap squashfs-tools xorriso \
    mtools dosfstools rsync gpg python3 python3-pyyaml git
  # live-build is Debian-specific; install from source on Fedora
  if ! command -v lb >/dev/null 2>&1; then
    log "Installing live-build from Debian source"
    TMPDIR=$(mktemp -d)
    curl -fsSL "http://ftp.debian.org/debian/pool/main/l/live-build/live-build_20230502.tar.gz" \
      -o "${TMPDIR}/live-build.tar.gz"
    tar -xzf "${TMPDIR}/live-build.tar.gz" -C "${TMPDIR}"
    $SUDO make -C "${TMPDIR}"/live-build-* install
    rm -rf "${TMPDIR}"
  fi
  ok "dnf dependencies installed"
}

install_deps_arch() {
  log "Installing dependencies (pacman)"
  $SUDO pacman -Sy --noconfirm \
    curl wget gnupg ca-certificates \
    debootstrap squashfs-tools libisoburn \
    mtools dosfstools rsync python python-yaml git
  # live-build via AUR
  if ! command -v lb >/dev/null 2>&1; then
    if command -v yay >/dev/null 2>&1; then
      yay -S --noconfirm live-build
    elif command -v paru >/dev/null 2>&1; then
      paru -S --noconfirm live-build
    else
      warn "live-build not found and no AUR helper available"
      warn "Install manually: https://aur.archlinux.org/packages/live-build"
    fi
  fi
  ok "pacman dependencies installed"
}

install_deps_macos() {
  warn "macOS detected — live-build is Linux-only"
  warn "ISO builds cannot run natively on macOS"
  warn "Options:"
  warn "  1. Use the cloud-init VM path (deploy/cloud-init/user-data.yaml)"
  warn "  2. Run a Linux VM locally (UTM, Parallels, VMware)"
  warn "  3. Register a remote Linux machine instead"
  warn ""
  warn "Continuing with gitlab-runner installation only..."
  if ! command -v brew >/dev/null 2>&1; then
    die "Homebrew not found. Install from https://brew.sh"
  fi
  brew install gitlab-runner
  ok "gitlab-runner installed via Homebrew"
  SKIP_REGISTER=0
}

install_gitlab_runner_linux() {
  if command -v gitlab-runner >/dev/null 2>&1; then
    ok "gitlab-runner already installed: $(gitlab-runner --version | head -1)"
    return
  fi

  log "Installing gitlab-runner"
  curl -fsSL "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" \
    | $SUDO bash 2>/dev/null || true

  case "${OS_ID}" in
    ubuntu|debian|linuxmint|pop)
      $SUDO apt-get install -y gitlab-runner ;;
    fedora|rhel|centos|rocky|almalinux)
      $SUDO dnf install -y gitlab-runner ;;
    arch|manjaro)
      $SUDO pacman -Sy --noconfirm gitlab-runner ;;
    *)
      # Fallback: download binary directly
      RUNNER_VERSION=$(curl -fsSL "https://gitlab.com/api/v4/projects/gitlab-org%2Fgitlab-runner/releases" \
        | grep -o '"tag_name":"v[^"]*"' | head -1 | cut -d'"' -f4)
      curl -fsSL \
        "https://gitlab-runner-downloads.s3.amazonaws.com/${RUNNER_VERSION}/binaries/gitlab-runner-linux-${ARCH_LABEL}" \
        -o /tmp/gitlab-runner
      $SUDO install -o root -g root -m 755 /tmp/gitlab-runner /usr/local/bin/gitlab-runner
      $SUDO useradd --system --shell /bin/bash --create-home --home-dir /home/gitlab-runner gitlab-runner 2>/dev/null || true
      $SUDO gitlab-runner install --user=gitlab-runner --working-directory=/home/gitlab-runner
      ;;
  esac

  $SUDO gitlab-runner start
  ok "gitlab-runner installed and started"
}

install_deps() {
  if [ "${SKIP_DEPS}" = "1" ]; then
    log "SKIP_DEPS=1 — skipping package installation"
    return
  fi

  case "${OS_ID}" in
    ubuntu|debian|linuxmint|pop|neon)
      install_deps_debian
      install_gitlab_runner_linux
      ;;
    fedora|rhel|centos|rocky|almalinux)
      install_deps_fedora
      install_gitlab_runner_linux
      ;;
    arch|manjaro|endeavouros)
      install_deps_arch
      install_gitlab_runner_linux
      ;;
    macos)
      install_deps_macos
      ;;
    *)
      # Try apt first, then dnf, then warn
      if command -v apt-get >/dev/null 2>&1; then
        install_deps_debian
        install_gitlab_runner_linux
      elif command -v dnf >/dev/null 2>&1; then
        install_deps_fedora
        install_gitlab_runner_linux
      else
        warn "Unknown OS '${OS_ID}' — skipping automatic dependency install"
        warn "Install manually: gitlab-runner, live-build, debootstrap, squashfs-tools, xorriso"
      fi
      ;;
  esac
}

# ── sudo config for live-build ────────────────────────────────────────────────

configure_sudo() {
  if [ "${OS_ID}" = "macos" ]; then return; fi

  SUDOERS_FILE="/etc/sudoers.d/gitlab-runner-livebuild"
  if [ ! -f "${SUDOERS_FILE}" ]; then
    log "Configuring passwordless sudo for live-build"
    # lb and debootstrap need root; restrict to just those binaries
    LB_PATH=$(command -v lb 2>/dev/null || echo /usr/bin/lb)
    DB_PATH=$(command -v debootstrap 2>/dev/null || echo /usr/sbin/debootstrap)
    printf 'gitlab-runner ALL=(ALL) NOPASSWD: %s, %s\n' "${LB_PATH}" "${DB_PATH}" \
      | $SUDO tee "${SUDOERS_FILE}" >/dev/null
    $SUDO chmod 440 "${SUDOERS_FILE}"
    ok "Sudoers configured: ${SUDOERS_FILE}"
  else
    ok "Sudoers already configured"
  fi
}

# ── Runner registration ───────────────────────────────────────────────────────

register_runner() {
  if [ "${SKIP_REGISTER}" = "1" ]; then
    log "SKIP_REGISTER=1 — skipping runner registration"
    return
  fi

  : "${GITLAB_RUNNER_TOKEN:?GITLAB_RUNNER_TOKEN must be set. Get it from:
  ${GITLAB_URL}/groups/openos-project/kde-ecosystem-deving/neon-deving/-/runners/new}"

  log "Registering runner: ${RUNNER_NAME}"
  log "  URL:  ${GITLAB_URL}"
  log "  Tags: ${RUNNER_TAGS}"
  log "  Concurrent: ${RUNNER_CONCURRENT}"

  $SUDO gitlab-runner register \
    --non-interactive \
    --url "${GITLAB_URL}" \
    --token "${GITLAB_RUNNER_TOKEN}" \
    --executor "shell" \
    --description "${RUNNER_NAME}" \
    --tag-list "${RUNNER_TAGS}" \
    --run-untagged false \
    --locked false

  # Set concurrent builds in config
  CONFIG="/etc/gitlab-runner/config.toml"
  if [ -f "${CONFIG}" ]; then
    $SUDO sed -i "s/^concurrent = .*/concurrent = ${RUNNER_CONCURRENT}/" "${CONFIG}"
    ok "Set concurrent = ${RUNNER_CONCURRENT} in ${CONFIG}"
  fi

  $SUDO gitlab-runner restart
  ok "Runner registered and restarted"
}

# ── Verify ────────────────────────────────────────────────────────────────────

verify() {
  log "Verifying installation"

  for BIN in gitlab-runner lb debootstrap; do
    if command -v "${BIN}" >/dev/null 2>&1; then
      ok "${BIN}: $(command -v ${BIN})"
    else
      warn "${BIN}: not found"
    fi
  done

  if command -v gitlab-runner >/dev/null 2>&1; then
    STATUS=$(gitlab-runner status 2>&1 | head -1 || echo "unknown")
    ok "gitlab-runner status: ${STATUS}"
  fi

  printf '\n'
  log "Done. Runner '${RUNNER_NAME}' should appear at:"
  printf '  %s/groups/openos-project/kde-ecosystem-deving/neon-deving/-/runners\n' "${GITLAB_URL}"
  printf '\n'
  printf 'To trigger a test build:\n'
  printf '  %s/openos-project/kde-ecosystem-deving/neon-deving/neon-user/-/pipelines/new\n' "${GITLAB_URL}"
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
  printf '\n'
  log "KDE Neon ISO Builder — Runner Setup"
  printf '\n'

  need_root
  detect_os
  check_prerequisites
  install_deps
  configure_sudo
  register_runner
  verify
}

main "$@"
