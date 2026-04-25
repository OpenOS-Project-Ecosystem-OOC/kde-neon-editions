#!/usr/bin/env bash
# setup-mirror.sh — configure GitLab pull mirroring for all four edition repos
# via the GitLab API.
#
# Source group: gitlab.com/openos-project/kde-ecosystem-deving/kde-groups/neon
# Each edition repo mirrors the seeds repo on its corresponding Neon branch.
# The build pipeline additionally clones livecd-rootfs, calamares-settings,
# and settings at build time using CI_JOB_TOKEN.
#
# Run this once after creating the edition repos on GitLab.
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
INTERNAL_BASE="https://gitlab.com/openos-project/kde-ecosystem-deving/kde-groups/neon/neon"

# Map: edition repo slug → source repo URL in kde-groups/neon + branch
declare -A REPOS=(
  ["neon-user"]="${INTERNAL_BASE}/seeds.git|Neon/release"
  ["neon-testing"]="${INTERNAL_BASE}/seeds.git|Neon/release"
  ["neon-developer-stable"]="${INTERNAL_BASE}/seeds.git|Neon/stable"
  ["neon-developer-unstable"]="${INTERNAL_BASE}/seeds.git|Neon/unstable"
)

api() {
  curl -fsSL \
    --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    --header "Content-Type: application/json" \
    "$@"
}

encode_path() {
  python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"
}

for REPO_SLUG in "${!REPOS[@]}"; do
  IFS='|' read -r UPSTREAM_URL UPSTREAM_BRANCH <<< "${REPOS[$REPO_SLUG]}"
  PROJECT_PATH="${GITLAB_GROUP}/${REPO_SLUG}"
  ENCODED_PATH=$(encode_path "${PROJECT_PATH}")

  echo "==> Configuring mirror for: ${PROJECT_PATH}"
  echo "    Source: ${UPSTREAM_URL} (${UPSTREAM_BRANCH})"

  api --request PUT \
    "${GITLAB_API_URL}/projects/${ENCODED_PATH}" \
    --data "{
      \"mirror\": true,
      \"import_url\": \"${UPSTREAM_URL}\",
      \"mirror_trigger_builds\": false,
      \"only_mirror_protected_branches\": false
    }" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'    Mirror enabled: {d.get(\"mirror\", False)}')
print(f'    Import URL:     {d.get(\"import_url\", \"(not set)\")}')
"
  echo "    Done."
done

echo ""
echo "Mirror configuration complete."
echo "GitLab will sync from kde-groups/neon on its default schedule (every 30 min)."
echo "To trigger an immediate sync, use:"
echo "  POST ${GITLAB_API_URL}/projects/<id>/mirror/pull"
echo "  or run: bash trigger-mirror-sync.sh"
