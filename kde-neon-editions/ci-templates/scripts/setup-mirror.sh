#!/usr/bin/env bash
# setup-mirror.sh — configure GitLab pull mirroring for all four edition repos
# via the GitLab API.
#
# Run this once after creating the repos on gitlab.com.
#
# Required:
#   GITLAB_TOKEN        — personal access token with api scope
#   GITLAB_GROUP        — e.g. openos-project/kde-ecosystem-deving/kde-groups/neon
#
# Optional:
#   GITLAB_API_URL      — defaults to https://gitlab.com/api/v4
set -euo pipefail

: "${GITLAB_TOKEN:?GITLAB_TOKEN must be set}"
: "${GITLAB_GROUP:?GITLAB_GROUP must be set}"

GITLAB_API_URL="${GITLAB_API_URL:-https://gitlab.com/api/v4}"

# Map: local repo slug → upstream invent.kde.org repo URL + branch
declare -A REPOS=(
  ["neon-user"]="https://invent.kde.org/neon/neon/seeds.git|Neon/release"
  ["neon-testing"]="https://invent.kde.org/neon/neon/seeds.git|Neon/release"
  ["neon-developer-stable"]="https://invent.kde.org/neon/neon/seeds.git|Neon/stable"
  ["neon-developer-unstable"]="https://invent.kde.org/neon/neon/seeds.git|Neon/unstable"
)

api() {
  curl -fsSL \
    --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    --header "Content-Type: application/json" \
    "$@"
}

encode_path() {
  # URL-encode a project path for GitLab API
  python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"
}

for REPO_SLUG in "${!REPOS[@]}"; do
  IFS='|' read -r UPSTREAM_URL UPSTREAM_BRANCH <<< "${REPOS[$REPO_SLUG]}"
  PROJECT_PATH="${GITLAB_GROUP}/${REPO_SLUG}"
  ENCODED_PATH=$(encode_path "${PROJECT_PATH}")

  echo "==> Configuring mirror for: ${PROJECT_PATH}"
  echo "    Upstream: ${UPSTREAM_URL} (${UPSTREAM_BRANCH})"

  # Enable pull mirroring on the project
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
echo "GitLab will sync from invent.kde.org on its default schedule (every 30 min)."
echo "To trigger an immediate sync, use:"
echo "  POST ${GITLAB_API_URL}/projects/<id>/mirror/pull"
