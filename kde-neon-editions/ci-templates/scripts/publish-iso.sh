#!/usr/bin/env bash
# publish-iso.sh — upload built ISOs to a remote host or GitLab Package Registry.
#
# Supports two publish targets (set PUBLISH_TARGET):
#   gitlab-packages  — GitLab Generic Package Registry (default)
#   rsync            — rsync over SSH to a file server
#
# Required variables:
#   EDITION          — edition name (user | testing | developer-stable | developer-unstable)
#   CI_PROJECT_ID    — set automatically by GitLab CI
#   CI_API_V4_URL    — set automatically by GitLab CI
#   GITLAB_TOKEN     — project token with write_packages scope
#
# For rsync target:
#   RSYNC_HOST       — destination host
#   RSYNC_PATH       — destination path (e.g. /srv/isos/neon)
#   SSH_PRIVATE_KEY  — SSH private key (file-type CI/CD variable)
set -euo pipefail

: "${EDITION:?EDITION must be set}"

PUBLISH_TARGET="${PUBLISH_TARGET:-gitlab-packages}"
TIMESTAMP=$(date -u +%Y%m%d)
PACKAGE_VERSION="${TIMESTAMP}-${CI_COMMIT_SHORT_SHA:-local}"

publish_gitlab() {
  : "${GITLAB_TOKEN:?GITLAB_TOKEN must be set for gitlab-packages target}"
  : "${CI_PROJECT_ID:?CI_PROJECT_ID must be set}"
  : "${CI_API_V4_URL:?CI_API_V4_URL must be set}"

  for FILE in *.iso *.iso.sha256 *.iso.sig; do
    [[ -f "${FILE}" ]] || continue
    echo "==> Uploading ${FILE} to GitLab Package Registry"
    curl --fail-with-body \
      --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
      --upload-file "${FILE}" \
      "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/kde-neon-${EDITION}/${PACKAGE_VERSION}/${FILE}"
    echo "    Uploaded: ${FILE}"
  done

  echo ""
  echo "Package URL:"
  echo "  ${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/kde-neon-${EDITION}/${PACKAGE_VERSION}/"
}

publish_rsync() {
  : "${RSYNC_HOST:?RSYNC_HOST must be set for rsync target}"
  : "${RSYNC_PATH:?RSYNC_PATH must be set for rsync target}"
  : "${SSH_PRIVATE_KEY:?SSH_PRIVATE_KEY must be set for rsync target}"

  mkdir -p ~/.ssh
  echo "${SSH_PRIVATE_KEY}" > ~/.ssh/id_ed25519
  chmod 600 ~/.ssh/id_ed25519
  ssh-keyscan "${RSYNC_HOST}" >> ~/.ssh/known_hosts 2>/dev/null

  DEST="${RSYNC_HOST}:${RSYNC_PATH}/${EDITION}/${TIMESTAMP}/"
  echo "==> Syncing ISOs to ${DEST}"
  rsync -avz --progress *.iso *.iso.sha256 *.iso.sig "${DEST}" 2>/dev/null || \
    rsync -avz --progress *.iso *.iso.sha256 "${DEST}"

  # Keep only the 4 most recent builds on the remote
  ssh "${RSYNC_HOST}" "ls -dt ${RSYNC_PATH}/${EDITION}/*/ | tail -n +5 | xargs rm -rf" || true
}

case "${PUBLISH_TARGET}" in
  gitlab-packages) publish_gitlab ;;
  rsync)           publish_rsync ;;
  *)
    echo "ERROR: Unknown PUBLISH_TARGET '${PUBLISH_TARGET}'. Use 'gitlab-packages' or 'rsync'." >&2
    exit 1
    ;;
esac

echo "==> Publish complete"
