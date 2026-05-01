#!/usr/bin/env bash
# setup-mirror.sh — configure upstream sync schedules for all four edition repos.
#
# GitLab pull mirroring requires Premium. On free tier, upstream sync is done
# via scheduled CI pipelines that run sync-upstream.sh every 30 minutes.
# This script creates those schedules via the API.
#
# Run this once after creating the edition repos on GitLab, or to re-create
# schedules if they were deleted.
#
# Required:
#   GITLAB_TOKEN        — personal access token with api scope
#   GITLAB_GROUP        — target group, e.g. openos-project/kde-ecosystem-deving/neon-deving
#
# Optional:
#   GITLAB_API_URL      — defaults to https://gitlab.com/api/v4
set -euo pipefail

: "${GITLAB_TOKEN:?GITLAB_TOKEN must be set}"
: "${GITLAB_GROUP:?GITLAB_GROUP must be set}"

GITLAB_API_URL="${GITLAB_API_URL:-https://gitlab.com/api/v4}"

# Stagger schedules by 5 min to avoid hammering upstream simultaneously
# Format: "repo_slug cron_expression"
REPOS="neon-user 0,30 * * * *
neon-testing 5,35 * * * *
neon-developer-stable 10,40 * * * *
neon-developer-unstable 15,45 * * * *"

encode_path() {
  printf '%s' "$1" | python3 -c "import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read(), safe=''))"
}

echo "Creating upstream sync schedules (every 30 min, staggered)..."
echo ""

echo "${REPOS}" | while read -r REPO_SLUG CRON; do
  PROJECT_PATH="${GITLAB_GROUP}/${REPO_SLUG}"
  ENCODED=$(encode_path "${PROJECT_PATH}")

  echo "==> ${PROJECT_PATH}"
  echo "    Cron: ${CRON}"

  RESULT=$(curl -fsSL \
    --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    --header "Content-Type: application/json" \
    --request POST \
    "${GITLAB_API_URL}/projects/${ENCODED}/pipeline_schedules" \
    --data "{\"description\":\"Sync upstream kde-groups/neon (every 30 min)\",\"ref\":\"main\",\"cron\":\"${CRON}\",\"cron_timezone\":\"UTC\",\"active\":true}")

  SCHED_ID=$(echo "${RESULT}" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
  ACTIVE=$(echo "${RESULT}" | grep -o '"active":[^,]*' | head -1 | cut -d: -f2)
  echo "    Schedule ID: ${SCHED_ID}  active: ${ACTIVE}"
  echo ""
done

echo "Done. Each edition repo will sync from kde-groups/neon every 30 minutes."
echo ""
echo "To trigger an immediate sync on a repo, run:"
echo "  POST ${GITLAB_API_URL}/projects/<encoded-path>/pipeline_schedules/<id>/play"
echo "  or: bash trigger-mirror-sync.sh"
