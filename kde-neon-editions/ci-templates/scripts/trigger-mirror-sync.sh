#!/usr/bin/env bash
# trigger-mirror-sync.sh — manually trigger an immediate upstream sync for
# all four edition repos by playing their scheduled pipeline.
#
# GitLab pull mirroring requires Premium. Sync is done via scheduled CI
# pipelines (sync-upstream.sh). This script plays those schedules on demand.
#
# Useful after upstream KDE Neon pushes a significant update and you don't
# want to wait for the next 30-minute window.
#
# Required:
#   GITLAB_TOKEN   — personal access token with api scope
#   GITLAB_GROUP   — e.g. openos-project/kde-ecosystem-deving/neon-deving
#
# Optional:
#   GITLAB_API_URL — defaults to https://gitlab.com/api/v4
set -euo pipefail

: "${GITLAB_TOKEN:?GITLAB_TOKEN must be set}"
: "${GITLAB_GROUP:?GITLAB_GROUP must be set}"

GITLAB_API_URL="${GITLAB_API_URL:-https://gitlab.com/api/v4}"

REPO_SLUGS="neon-user neon-testing neon-developer-stable neon-developer-unstable"

encode_path() {
  printf '%s' "$1" | python3 -c "import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read(), safe=''))"
}

for REPO_SLUG in ${REPO_SLUGS}; do
  PROJECT_PATH="${GITLAB_GROUP}/${REPO_SLUG}"
  ENCODED=$(encode_path "${PROJECT_PATH}")

  echo "==> ${PROJECT_PATH}"

  # Find the sync schedule (first schedule on the repo)
  SCHED_ID=$(curl -fsSL \
    --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    "${GITLAB_API_URL}/projects/${ENCODED}/pipeline_schedules" \
    | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)

  if [ -z "${SCHED_ID}" ]; then
    echo "    WARNING: No schedule found — run setup-mirror.sh first"
    continue
  fi

  HTTP_STATUS=$(curl -fsSL -o /dev/null -w "%{http_code}" \
    --request POST \
    --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    "${GITLAB_API_URL}/projects/${ENCODED}/pipeline_schedules/${SCHED_ID}/play")

  if [ "${HTTP_STATUS}" = "201" ]; then
    echo "    Sync pipeline triggered (schedule ${SCHED_ID})"
  else
    echo "    WARNING: HTTP ${HTTP_STATUS} — schedule ${SCHED_ID}"
  fi
done

echo ""
echo "Sync pipelines triggered. Check progress at:"
echo "  https://gitlab.com/${GITLAB_GROUP}/<repo>/-/pipelines"
