#!/usr/bin/env bash
# trigger-mirror-sync.sh — manually trigger an immediate pull mirror sync
# for all four edition repos via the GitLab API.
#
# Useful after upstream KDE Neon pushes a significant update.
set -euo pipefail

: "${GITLAB_TOKEN:?GITLAB_TOKEN must be set}"
: "${GITLAB_GROUP:?GITLAB_GROUP must be set}"

GITLAB_API_URL="${GITLAB_API_URL:-https://gitlab.com/api/v4}"

REPO_SLUGS=(
  "neon-user"
  "neon-testing"
  "neon-developer-stable"
  "neon-developer-unstable"
)

encode_path() {
  python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"
}

for REPO_SLUG in "${REPO_SLUGS[@]}"; do
  PROJECT_PATH="${GITLAB_GROUP}/${REPO_SLUG}"
  ENCODED_PATH=$(encode_path "${PROJECT_PATH}")

  echo "==> Triggering mirror sync: ${PROJECT_PATH}"
  HTTP_STATUS=$(curl -fsSL -o /dev/null -w "%{http_code}" \
    --request POST \
    --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    "${GITLAB_API_URL}/projects/${ENCODED_PATH}/mirror/pull")

  if [[ "${HTTP_STATUS}" == "200" ]]; then
    echo "    Sync triggered successfully."
  else
    echo "    WARNING: Unexpected HTTP status ${HTTP_STATUS}"
  fi
done
