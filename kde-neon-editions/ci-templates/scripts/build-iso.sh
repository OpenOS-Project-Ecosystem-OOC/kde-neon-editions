#!/usr/bin/env bash
# build-iso.sh — build a KDE Neon edition ISO using live-build.
#
# Clones seeds, livecd-rootfs, calamares-settings, and settings from the
# internal GitLab mirror at kde-groups/neon, then runs lb build.
#
# Required environment variables (set in .gitlab-ci.yml):
#   EDITION         — user | testing | developer-stable | developer-unstable
#   NEON_ARCHIVE    — e.g. http://archive.neon.kde.org/user
#   UBUNTU_SERIES   — e.g. noble
#   NEON_BRANCH     — e.g. Neon/release
#   NEON_ARCHIVE_KEY — GPG key fingerprint for the Neon archive
#
# GitLab CI provides automatically:
#   CI_JOB_TOKEN    — used to clone internal repos without a PAT
#   CI_SERVER_HOST  — e.g. gitlab.com
#
# Optional:
#   BUILD_DIR       — working directory for live-build (default: ./build)
#   ISO_NAME        — output filename prefix (default: kde-neon-${EDITION})
set -euo pipefail

: "${EDITION:?EDITION must be set}"
: "${NEON_ARCHIVE:?NEON_ARCHIVE must be set}"
: "${UBUNTU_SERIES:?UBUNTU_SERIES must be set}"
: "${NEON_BRANCH:?NEON_BRANCH must be set}"

BUILD_DIR="${BUILD_DIR:-./build}"
ISO_NAME="${ISO_NAME:-kde-neon-${EDITION}}"
MANIFEST="manifests/${EDITION}.yaml"

# Internal GitLab group — read from manifest, with fallback
INTERNAL_GROUP=$(python3 -c "
import yaml, sys
m = yaml.safe_load(open('${MANIFEST}'))
print(m.get('source_group', 'openos-project/kde-ecosystem-deving/kde-groups/neon/neon'))
")
CI_SERVER_HOST="${CI_SERVER_HOST:-gitlab.com}"

# Clone helper — uses CI_JOB_TOKEN for auth inside pipelines,
# falls back to unauthenticated for local runs
clone_internal() {
  local REPO="$1"
  local BRANCH="$2"
  local DEST="$3"

  local URL
  if [[ -n "${CI_JOB_TOKEN:-}" ]]; then
    URL="https://gitlab-ci-token:${CI_JOB_TOKEN}@${CI_SERVER_HOST}/${INTERNAL_GROUP}/${REPO}.git"
  else
    URL="https://${CI_SERVER_HOST}/${INTERNAL_GROUP}/${REPO}.git"
  fi

  echo "==> Cloning ${REPO} (${BRANCH}) -> ${DEST}"
  git clone --depth=1 --branch "${BRANCH}" "${URL}" "${DEST}"
}

echo "==> Building KDE Neon ${EDITION} ISO"
echo "    Archive:  ${NEON_ARCHIVE}"
echo "    Series:   ${UBUNTU_SERIES}"
echo "    Branch:   ${NEON_BRANCH}"
echo "    Manifest: ${MANIFEST}"

# ── Clone internal source repos ───────────────────────────────────────────────

WORK_DIR="$(mktemp -d /tmp/neon-build-XXXXXX)"
trap "rm -rf ${WORK_DIR}" EXIT

clone_internal "seeds"              "${NEON_BRANCH}" "${WORK_DIR}/seeds"
clone_internal "livecd-rootfs"      "${NEON_BRANCH}" "${WORK_DIR}/livecd-rootfs"
clone_internal "calamares-settings" "${NEON_BRANCH}" "${WORK_DIR}/calamares-settings"
clone_internal "settings"           "${NEON_BRANCH}" "${WORK_DIR}/settings"

echo "==> Source repos cloned to ${WORK_DIR}"

# ── Parse manifest ────────────────────────────────────────────────────────────

parse_packages() {
  local key="$1"
  python3 - "${MANIFEST}" "${key}" <<'EOF'
import sys, yaml
manifest = yaml.safe_load(open(sys.argv[1]))
pkgs = manifest.get(sys.argv[2]) or []
if isinstance(pkgs, list):
    print(" ".join(str(p).split("#")[0].strip() for p in pkgs if p and not str(p).startswith("#")))
EOF
}

BASE_PKGS=$(parse_packages "base_packages")
PLASMA_PKGS=$(parse_packages "plasma_packages")
APP_PKGS=$(parse_packages "application_packages")
NEON_PKGS=$(parse_packages "neon_packages")
INSTALLER_PKGS=$(parse_packages "installer_packages")
DEV_PKGS=$(parse_packages "developer_extras")
TEST_PKGS=$(parse_packages "testing_extras")

ALL_PACKAGES="${BASE_PKGS} ${PLASMA_PKGS} ${APP_PKGS} ${NEON_PKGS} ${INSTALLER_PKGS} ${DEV_PKGS} ${TEST_PKGS}"

# ── Import Neon archive key ───────────────────────────────────────────────────

echo "==> Importing Neon archive signing key"
gpg --keyserver keyserver.ubuntu.com --recv-keys "${NEON_ARCHIVE_KEY:-45F4C354638D1F29}"
gpg --export "${NEON_ARCHIVE_KEY:-45F4C354638D1F29}" > /etc/apt/trusted.gpg.d/neon-archive.gpg

# ── Set up live-build config ──────────────────────────────────────────────────

echo "==> Initialising live-build config"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

lb config \
  --mode ubuntu \
  --distribution "${UBUNTU_SERIES}" \
  --architectures amd64 \
  --binary-images iso-hybrid \
  --bootloader grub-efi \
  --debian-installer live \
  --debian-installer-gui true \
  --apt-options "--yes --no-install-recommends" \
  --mirror-bootstrap "http://archive.ubuntu.com/ubuntu/" \
  --mirror-binary "http://archive.ubuntu.com/ubuntu/" \
  --mirror-binary-security "http://security.ubuntu.com/ubuntu/" \
  --security true \
  --updates true \
  --backports false \
  --iso-application "KDE neon ${EDITION}" \
  --iso-publisher "OpenOS Project / KDE neon" \
  --iso-volume "KDE neon ${EDITION^}" \
  --memtest none \
  --win32-loader false

# ── Add Neon apt source ───────────────────────────────────────────────────────

echo "==> Adding Neon archive to live-build apt sources"
mkdir -p config/archives
cat > config/archives/neon.list.binary <<EOF
deb ${NEON_ARCHIVE} ${UBUNTU_SERIES} main
EOF
cat > config/archives/neon.list.chroot <<EOF
deb ${NEON_ARCHIVE} ${UBUNTU_SERIES} main
EOF
cp /etc/apt/trusted.gpg.d/neon-archive.gpg config/archives/neon.key.binary
cp /etc/apt/trusted.gpg.d/neon-archive.gpg config/archives/neon.key.chroot

# ── Seeds → package list ──────────────────────────────────────────────────────

echo "==> Installing seeds from internal repo"
mkdir -p config/package-lists

# Seeds format: lines starting with ' * ' are package entries
SEED_FILE="${WORK_DIR}/seeds/neon-desktop"
if [[ -f "${SEED_FILE}" ]]; then
  echo "    Using seeds/neon-desktop"
  grep '^ \* ' "${SEED_FILE}" | sed 's/^ \* //' | cut -d' ' -f1 \
    > config/package-lists/neon-seeds.list.chroot
fi

# Append manifest packages (covers edition-specific extras not in seeds)
echo "${ALL_PACKAGES}" | tr ' ' '\n' | grep -v '^$' | sort -u \
  >> config/package-lists/neon-${EDITION}.list.chroot

# ── livecd-rootfs hooks ───────────────────────────────────────────────────────

echo "==> Installing livecd-rootfs hooks"
LIVECD_HOOKS="${WORK_DIR}/livecd-rootfs/live-build/ubuntu-core"
if [[ -d "${LIVECD_HOOKS}" ]]; then
  cp -r "${LIVECD_HOOKS}/." config/hooks/live/ 2>/dev/null || true
  echo "    Copied livecd-rootfs ubuntu-core hooks"
fi

# ── calamares-settings ────────────────────────────────────────────────────────

echo "==> Installing calamares-settings"
CALAMARES_SRC="${WORK_DIR}/calamares-settings"
if [[ -d "${CALAMARES_SRC}" ]]; then
  mkdir -p config/includes.chroot/etc/calamares
  cp -r "${CALAMARES_SRC}/." config/includes.chroot/etc/calamares/ 2>/dev/null || true
  echo "    Copied calamares-settings"
fi

# ── neon-settings ─────────────────────────────────────────────────────────────

echo "==> Installing neon-settings"
SETTINGS_SRC="${WORK_DIR}/settings"
if [[ -d "${SETTINGS_SRC}" ]]; then
  for DIR in etc usr; do
    if [[ -d "${SETTINGS_SRC}/${DIR}" ]]; then
      mkdir -p "config/includes.chroot/${DIR}"
      cp -r "${SETTINGS_SRC}/${DIR}/." "config/includes.chroot/${DIR}/" 2>/dev/null || true
    fi
  done
  echo "    Copied neon-settings overlays"
fi

# ── Additional hooks ──────────────────────────────────────────────────────────

mkdir -p config/hooks/live

cat > config/hooks/live/0010-lsb-release.hook.chroot <<HOOK
#!/bin/sh
set -e
cat > /etc/lsb-release <<LSB
DISTRIB_ID=neon
DISTRIB_RELEASE=${UBUNTU_SERIES}
DISTRIB_CODENAME=${UBUNTU_SERIES}
DISTRIB_DESCRIPTION="KDE neon ${EDITION}"
LSB
HOOK

cat > config/hooks/live/0020-enable-sddm.hook.chroot <<HOOK
#!/bin/sh
set -e
systemctl enable sddm || true
HOOK

cat > config/hooks/live/0030-default-session.hook.chroot <<HOOK
#!/bin/sh
set -e
mkdir -p /var/lib/AccountsService/users
cat > /var/lib/AccountsService/users/neon <<SESSION
[User]
Session=plasma
SystemAccount=false
SESSION
HOOK

chmod +x config/hooks/live/*.hook.chroot 2>/dev/null || true

# ── Build ─────────────────────────────────────────────────────────────────────

echo "==> Running lb build (this takes 20-40 minutes)"
lb build 2>&1 | tee ../build.log

# ── Rename output ─────────────────────────────────────────────────────────────

cd ..
TIMESTAMP=$(date -u +%Y%m%d)
FINAL_NAME="${ISO_NAME}-${TIMESTAMP}-amd64.iso"

if ls "${BUILD_DIR}"/*.iso 2>/dev/null | head -1 | grep -q '.iso'; then
  mv "${BUILD_DIR}"/*.iso "${FINAL_NAME}"
  echo "==> ISO ready: ${FINAL_NAME}"
else
  echo "ERROR: No ISO produced. Check build.log for details." >&2
  exit 1
fi
