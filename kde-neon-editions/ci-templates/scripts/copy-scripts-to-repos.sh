#!/usr/bin/env bash
# copy-scripts-to-repos.sh — copy shared scripts into each edition repo.
#
# Run this after cloning all repos side-by-side, or after updating a script
# in ci-templates. Symlinks work in a mono-repo checkout but not across
# separate GitLab repos, so each repo needs its own copy of the scripts.
#
# Expected layout:
#   ./ci-templates/
#   ./neon-user/
#   ./neon-testing/
#   ./neon-developer-stable/
#   ./neon-developer-unstable/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

EDITIONS=(
  "neon-user"
  "neon-testing"
  "neon-developer-stable"
  "neon-developer-unstable"
)

SCRIPTS=(
  "build-iso.sh"
  "checksum-iso.sh"
  "publish-iso.sh"
  "smoke-test-iso.sh"
  "sync-upstream.sh"
  "validate-manifest.py"
)

for EDITION in "${EDITIONS[@]}"; do
  DEST="${ROOT}/${EDITION}/scripts"
  if [[ ! -d "${DEST}" ]]; then
    echo "WARNING: ${DEST} not found — skipping ${EDITION}"
    continue
  fi

  echo "==> Copying scripts to ${EDITION}/scripts/"
  for SCRIPT in "${SCRIPTS[@]}"; do
    SRC="${SCRIPT_DIR}/${SCRIPT}"
    # Replace symlink with real file if needed
    if [[ -L "${DEST}/${SCRIPT}" ]]; then
      rm "${DEST}/${SCRIPT}"
    fi
    cp "${SRC}" "${DEST}/${SCRIPT}"
    chmod +x "${DEST}/${SCRIPT}" 2>/dev/null || true
    echo "    ${SCRIPT}"
  done
done

echo ""
echo "Done. Commit the scripts/ directories in each edition repo."
