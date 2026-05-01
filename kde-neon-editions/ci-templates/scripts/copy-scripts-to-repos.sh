#!/usr/bin/env bash
# copy-scripts-to-repos.sh — copy shared scripts into each edition repo.
#
# Two modes:
#
#   Local (default):
#     Run after cloning all repos side-by-side. Copies files on disk.
#     Commit the result in each edition repo manually.
#
#   CI (--ci flag):
#     Reads each script from the local checkout and commits it directly
#     to each edition repo via the GitLab Repository Files API.
#     Requires GITLAB_TOKEN (write_repository) and CI_SERVER_URL.
#
# Expected layout for local mode:
#   ./ci-templates/
#   ./neon-user/
#   ./neon-testing/
#   ./neon-developer-stable/
#   ./neon-developer-unstable/
set -euo pipefail

CI_MODE=false
if [ "${1:-}" = "--ci" ]; then
  CI_MODE=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

EDITIONS="neon-user neon-testing neon-developer-stable neon-developer-unstable"

SCRIPTS="
build-iso.sh
checksum-iso.sh
publish-iso.sh
smoke-test-iso.sh
sync-upstream.sh
validate-manifest.py
bootstrap-scripts.sh
"

# ── Local mode ────────────────────────────────────────────────────────────────

if [ "${CI_MODE}" = "false" ]; then
  for EDITION in ${EDITIONS}; do
    DEST="${ROOT}/${EDITION}/scripts"
    if [ ! -d "${DEST}" ]; then
      echo "WARNING: ${DEST} not found — skipping ${EDITION}"
      continue
    fi

    echo "==> Copying scripts to ${EDITION}/scripts/"
    for SCRIPT in ${SCRIPTS}; do
      SCRIPT="$(echo "${SCRIPT}" | tr -d '[:space:]')"
      [ -z "${SCRIPT}" ] && continue
      SRC="${SCRIPT_DIR}/${SCRIPT}"
      [ -f "${SRC}" ] || { echo "    WARNING: ${SRC} not found — skipping"; continue; }
      # Replace symlink with real file if needed
      [ -L "${DEST}/${SCRIPT}" ] && rm "${DEST}/${SCRIPT}"
      cp "${SRC}" "${DEST}/${SCRIPT}"
      chmod +x "${DEST}/${SCRIPT}" 2>/dev/null || true
      echo "    ${SCRIPT}"
    done
  done

  echo ""
  echo "Done. Commit the scripts/ directories in each edition repo."
  exit 0
fi

# ── CI mode — push via GitLab API ─────────────────────────────────────────────

: "${GITLAB_TOKEN:?GITLAB_TOKEN must be set in CI mode}"
GITLAB_API="${CI_API_V4_URL:-https://gitlab.com/api/v4}"
GITLAB_GROUP="${GITLAB_GROUP:-openos-project/kde-ecosystem-deving/neon-deving}"
COMMIT_BRANCH="main"
COMMIT_MSG="ci: sync scripts from kde-neon-editions ci-templates (${CI_COMMIT_SHORT_SHA:-manual})"

encode_path() {
  printf '%s' "$1" | python3 -c "import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read(), safe=''))"
}

b64() {
  base64 -w 0 "$1"
}

api_file() {
  local METHOD="$1" PROJECT_ENC="$2" FILE_PATH="$3" CONTENT_B64="$4"
  curl -fsSL \
    --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    --header "Content-Type: application/json" \
    --request "${METHOD}" \
    "${GITLAB_API}/projects/${PROJECT_ENC}/repository/files/$(encode_path "${FILE_PATH}")" \
    --data "{
      \"branch\": \"${COMMIT_BRANCH}\",
      \"content\": \"${CONTENT_B64}\",
      \"encoding\": \"base64\",
      \"commit_message\": \"${COMMIT_MSG}\"
    }"
}

ERRORS=0

for EDITION in ${EDITIONS}; do
  PROJECT_PATH="${GITLAB_GROUP}/${EDITION}"
  PROJECT_ENC=$(encode_path "${PROJECT_PATH}")
  echo "==> ${PROJECT_PATH}"

  for SCRIPT in ${SCRIPTS}; do
    SCRIPT="$(echo "${SCRIPT}" | tr -d '[:space:]')"
    [ -z "${SCRIPT}" ] && continue
    SRC="${SCRIPT_DIR}/${SCRIPT}"
    [ -f "${SRC}" ] || { echo "    WARNING: ${SRC} not found — skipping"; continue; }

    DEST_PATH="scripts/${SCRIPT}"
    CONTENT_B64=$(b64 "${SRC}")

    # Try update first; fall back to create if file doesn't exist yet
    HTTP=$(curl -fsSL -o /dev/null -w "%{http_code}" \
      --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
      "${GITLAB_API}/projects/${PROJECT_ENC}/repository/files/$(encode_path "${DEST_PATH}")?ref=${COMMIT_BRANCH}" 2>/dev/null || echo "000")

    if [ "${HTTP}" = "200" ]; then
      METHOD="PUT"
    else
      METHOD="POST"
    fi

    RESULT=$(api_file "${METHOD}" "${PROJECT_ENC}" "${DEST_PATH}" "${CONTENT_B64}" 2>&1)
    if echo "${RESULT}" | grep -q '"file_path"'; then
      echo "    ${METHOD} ${DEST_PATH} — ok"
    else
      echo "    ERROR on ${DEST_PATH}: ${RESULT}" >&2
      ERRORS=$((ERRORS + 1))
    fi
  done

  echo ""
done

if [ "${ERRORS}" -gt 0 ]; then
  echo "ERROR: ${ERRORS} file(s) failed to sync." >&2
  exit 1
fi

echo "All scripts synced to edition repos."
