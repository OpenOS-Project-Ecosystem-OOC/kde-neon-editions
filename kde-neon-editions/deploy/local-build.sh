#!/usr/bin/env bash
# local-build.sh — build a KDE Neon edition ISO on any Linux machine
#                  without needing a GitLab runner.
#
# Wraps build-iso.sh with local dependency checks, optional Docker/Podman
# fallback for machines without live-build, and clean workspace management.
#
# Usage:
#   bash deploy/local-build.sh --edition user
#   bash deploy/local-build.sh --edition testing --no-cache
#   bash deploy/local-build.sh --edition developer-unstable --docker
#
# Options:
#   --edition   <name>   user | testing | developer-stable | developer-unstable
#   --docker             run inside a privileged Docker/Podman container
#                        (use on machines without native live-build support)
#   --no-cache           skip debootstrap cache (forces fresh base system)
#   --output    <dir>    where to write the ISO (default: ./output)
#   --workdir   <dir>    live-build working directory (default: /tmp/neon-build-<edition>)
#   --dry-run            print what would run, don't execute
#
# Environment variables (override manifest defaults):
#   NEON_ARCHIVE         apt archive URL
#   UBUNTU_SERIES        Ubuntu codename (e.g. noble)
#   NEON_BRANCH          upstream branch (e.g. Neon/release)
#   NEON_ARCHIVE_KEY     GPG key fingerprint
#   GPG_SIGNING_KEY      sign the ISO with this key fingerprint
#   GPG_PRIVATE_KEY      armored private key (for signing)

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────

EDITION=""
USE_DOCKER=false
NO_CACHE=false
DRY_RUN=false
OUTPUT_DIR="./output"
WORK_DIR=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Argument parsing ──────────────────────────────────────────────────────────

while [ $# -gt 0 ]; do
  case "$1" in
    --edition)   EDITION="$2";    shift 2 ;;
    --docker)    USE_DOCKER=true; shift ;;
    --no-cache)  NO_CACHE=true;   shift ;;
    --dry-run)   DRY_RUN=true;    shift ;;
    --output)    OUTPUT_DIR="$2"; shift 2 ;;
    --workdir)   WORK_DIR="$2";   shift 2 ;;
    -h|--help)
      sed -n '2,30p' "$0" | grep '^#' | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

: "${EDITION:?--edition is required. Choose: user | testing | developer-stable | developer-unstable}"

WORK_DIR="${WORK_DIR:-/tmp/neon-build-${EDITION}}"

# ── Edition → manifest defaults ───────────────────────────────────────────────

case "${EDITION}" in
  user)
    NEON_ARCHIVE="${NEON_ARCHIVE:-http://archive.neon.kde.org/user}"
    NEON_BRANCH="${NEON_BRANCH:-Neon/release}"
    UBUNTU_SERIES="${UBUNTU_SERIES:-noble}"
    NEON_ARCHIVE_KEY="${NEON_ARCHIVE_KEY:-45F4C354638D1F29}"
    ;;
  testing)
    NEON_ARCHIVE="${NEON_ARCHIVE:-http://archive.neon.kde.org/testing}"
    NEON_BRANCH="${NEON_BRANCH:-Neon/release}"
    UBUNTU_SERIES="${UBUNTU_SERIES:-noble}"
    NEON_ARCHIVE_KEY="${NEON_ARCHIVE_KEY:-45F4C354638D1F29}"
    ;;
  developer-stable)
    NEON_ARCHIVE="${NEON_ARCHIVE:-http://archive.neon.kde.org/dev/stable}"
    NEON_BRANCH="${NEON_BRANCH:-Neon/stable}"
    UBUNTU_SERIES="${UBUNTU_SERIES:-noble}"
    NEON_ARCHIVE_KEY="${NEON_ARCHIVE_KEY:-45F4C354638D1F29}"
    ;;
  developer-unstable)
    NEON_ARCHIVE="${NEON_ARCHIVE:-http://archive.neon.kde.org/dev/unstable}"
    NEON_BRANCH="${NEON_BRANCH:-Neon/unstable}"
    UBUNTU_SERIES="${UBUNTU_SERIES:-noble}"
    NEON_ARCHIVE_KEY="${NEON_ARCHIVE_KEY:-45F4C354638D1F29}"
    ;;
  *)
    echo "ERROR: Unknown edition '${EDITION}'" >&2
    echo "       Choose: user | testing | developer-stable | developer-unstable" >&2
    exit 1
    ;;
esac

export EDITION NEON_ARCHIVE NEON_BRANCH UBUNTU_SERIES NEON_ARCHIVE_KEY
export BUILD_DIR="${WORK_DIR}/lb"
export ISO_NAME="kde-neon-${EDITION}"

# ── Helpers ───────────────────────────────────────────────────────────────────

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

run() {
  if [ "${DRY_RUN}" = "true" ]; then
    printf '\033[2m[dry-run]\033[0m %s\n' "$*"
  else
    "$@"
  fi
}

# ── Prerequisite checks ───────────────────────────────────────────────────────

check_native_prereqs() {
  local MISSING=""

  for BIN in lb debootstrap xorriso git python3; do
    command -v "${BIN}" >/dev/null 2>&1 || MISSING="${MISSING} ${BIN}"
  done

  if [ -n "${MISSING}" ]; then
    warn "Missing binaries:${MISSING}"
    return 1
  fi

  if ! losetup -f >/dev/null 2>&1; then
    warn "Loop devices not available (running in a container?)"
    return 1
  fi

  if [ "$(id -u)" -ne 0 ] && ! sudo -n lb --version >/dev/null 2>&1; then
    warn "live-build needs root or passwordless sudo for lb"
    return 1
  fi

  return 0
}

check_docker_prereqs() {
  if command -v docker >/dev/null 2>&1; then
    DOCKER_CMD="docker"
  elif command -v podman >/dev/null 2>&1; then
    DOCKER_CMD="podman"
  else
    die "Neither docker nor podman found. Install one or use a native Linux host."
  fi
  ok "Container runtime: ${DOCKER_CMD}"
}

# ── Native build ──────────────────────────────────────────────────────────────

build_native() {
  log "Building ${EDITION} ISO natively"
  log "  Archive:  ${NEON_ARCHIVE}"
  log "  Branch:   ${NEON_BRANCH}"
  log "  Series:   ${UBUNTU_SERIES}"
  log "  Workdir:  ${WORK_DIR}"

  mkdir -p "${WORK_DIR}" "${OUTPUT_DIR}"

  # Run from the edition directory so manifests/ and scripts/ are in place
  EDITION_DIR="${REPO_ROOT}/neon-${EDITION}"
  [ -d "${EDITION_DIR}" ] || die "Edition directory not found: ${EDITION_DIR}"

  cd "${EDITION_DIR}"

  if [ "${NO_CACHE}" = "true" ]; then
    log "Clearing debootstrap cache"
    run rm -rf .cache/debootstrap/
  fi

  # Use local scripts/ (Option B bootstrap)
  export SCRIPTS_DIR="${EDITION_DIR}/scripts"

  run bash "${SCRIPTS_DIR}/build-iso.sh"
  run bash "${SCRIPTS_DIR}/checksum-iso.sh"

  # Move output to requested directory
  run mkdir -p "${OUTPUT_DIR}"
  run mv *.iso *.iso.sha256 *.iso.sig "${OUTPUT_DIR}/" 2>/dev/null || true

  ok "ISO written to ${OUTPUT_DIR}/"
}

# ── Docker/Podman build ───────────────────────────────────────────────────────

build_docker() {
  log "Building ${EDITION} ISO inside privileged container (${DOCKER_CMD})"
  log "  Image: ubuntu:noble"
  log "  This requires --privileged for loop device access"

  EDITION_DIR="${REPO_ROOT}/neon-${EDITION}"
  [ -d "${EDITION_DIR}" ] || die "Edition directory not found: ${EDITION_DIR}"

  mkdir -p "${OUTPUT_DIR}"

  # Build the apt install list from the same set used in iso-build.yml
  DEPS="live-build ubuntu-defaults-builder debootstrap squashfs-tools \
    xorriso isolinux syslinux-common grub-efi-amd64-bin grub-pc-bin \
    mtools dosfstools rsync wget curl gpg ca-certificates python3 python3-yaml git"

  CACHE_MOUNT=""
  if [ "${NO_CACHE}" = "false" ]; then
    mkdir -p "${WORK_DIR}/.cache/debootstrap"
    CACHE_MOUNT="-v ${WORK_DIR}/.cache/debootstrap:/workspace/.cache/debootstrap"
  fi

  run ${DOCKER_CMD} run --rm \
    --privileged \
    --device /dev/loop-control \
    -v "${EDITION_DIR}:/workspace" \
    -v "${OUTPUT_DIR}:/output" \
    ${CACHE_MOUNT} \
    -e EDITION="${EDITION}" \
    -e NEON_ARCHIVE="${NEON_ARCHIVE}" \
    -e NEON_BRANCH="${NEON_BRANCH}" \
    -e UBUNTU_SERIES="${UBUNTU_SERIES}" \
    -e NEON_ARCHIVE_KEY="${NEON_ARCHIVE_KEY}" \
    -e BUILD_DIR="/workspace/lb" \
    -e ISO_NAME="${ISO_NAME}" \
    -e SCRIPTS_DIR="/workspace/scripts" \
    -e GPG_SIGNING_KEY="${GPG_SIGNING_KEY:-}" \
    -e GPG_PRIVATE_KEY="${GPG_PRIVATE_KEY:-}" \
    ubuntu:noble \
    bash -c "
      set -euo pipefail
      apt-get update -qq
      apt-get install -y --no-install-recommends ${DEPS}
      cd /workspace
      bash scripts/build-iso.sh
      bash scripts/checksum-iso.sh
      mv *.iso *.iso.sha256 /output/ 2>/dev/null || true
      echo 'ISO written to /output/'
    "

  ok "ISO written to ${OUTPUT_DIR}/"
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
  printf '\n'
  log "KDE Neon Local ISO Builder"
  log "Edition: ${EDITION}"
  printf '\n'

  if [ "${USE_DOCKER}" = "true" ]; then
    check_docker_prereqs
    build_docker
  elif check_native_prereqs; then
    ok "Native prerequisites satisfied"
    build_native
  else
    warn "Native prerequisites not met — trying Docker/Podman fallback"
    warn "Pass --docker explicitly to skip this check next time"
    check_docker_prereqs
    build_docker
  fi

  printf '\n'
  log "Build complete"
  ls -lh "${OUTPUT_DIR}"/*.iso 2>/dev/null || true
}

main "$@"
