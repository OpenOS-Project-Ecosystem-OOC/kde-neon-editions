#!/usr/bin/env bash
# build-iso.sh — build a KDE Neon edition ISO using live-build.
#
# Reads configuration from the edition's manifest YAML and constructs
# a live-build config directory, then runs lb build.
#
# Required environment variables (set in .gitlab-ci.yml):
#   EDITION         — user | testing | developer-stable | developer-unstable
#   NEON_ARCHIVE    — e.g. http://archive.neon.kde.org/user
#   UBUNTU_SERIES   — e.g. noble
#   NEON_ARCHIVE_KEY — GPG key fingerprint for the Neon archive
#
# Optional:
#   BUILD_DIR       — working directory for live-build (default: ./build)
#   ISO_NAME        — output filename prefix (default: kde-neon-${EDITION})
set -euo pipefail

: "${EDITION:?EDITION must be set}"
: "${NEON_ARCHIVE:?NEON_ARCHIVE must be set}"
: "${UBUNTU_SERIES:?UBUNTU_SERIES must be set}"

BUILD_DIR="${BUILD_DIR:-./build}"
ISO_NAME="${ISO_NAME:-kde-neon-${EDITION}}"
MANIFEST="manifests/${EDITION}.yaml"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Building KDE Neon ${EDITION} ISO"
echo "    Archive:  ${NEON_ARCHIVE}"
echo "    Series:   ${UBUNTU_SERIES}"
echo "    Manifest: ${MANIFEST}"

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

# ── Package list ──────────────────────────────────────────────────────────────

echo "==> Writing package list"
mkdir -p config/package-lists
echo "${ALL_PACKAGES}" | tr ' ' '\n' | grep -v '^$' | sort -u \
  > config/package-lists/neon-${EDITION}.list.chroot

# ── Hooks ─────────────────────────────────────────────────────────────────────

echo "==> Installing build hooks"
mkdir -p config/hooks/live

# Set lsb-release for the edition
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

# Enable SDDM
cat > config/hooks/live/0020-enable-sddm.hook.chroot <<HOOK
#!/bin/sh
set -e
systemctl enable sddm || true
HOOK

# Set default session
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

chmod +x config/hooks/live/*.hook.chroot

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
