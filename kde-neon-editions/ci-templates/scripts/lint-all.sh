#!/usr/bin/env bash
# lint-all.sh — run all lint checks across every edition from the root repo.
#
# Checks:
#   1. Manifest YAML validation (all four editions)
#   2. shellcheck on all scripts in ci-templates/scripts/
#   3. GitLab CI YAML lint on root + all edition .gitlab-ci.yml files
#
# Required for CI YAML lint:
#   GITLAB_TOKEN   — read_api scope is sufficient
#   CI_API_V4_URL  — set automatically in GitLab CI (default: https://gitlab.com/api/v4)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SCRIPT_DIR}/../.."
CI_API_V4_URL="${CI_API_V4_URL:-https://gitlab.com/api/v4}"

EDITIONS=(user testing developer-stable developer-unstable)
EDITION_DIRS=(neon-user neon-testing neon-developer-stable neon-developer-unstable)

ERRORS=0

# ── 1. Manifest validation ────────────────────────────────────────────────────

echo "════════════════════════════════════════"
echo "  1. Manifest validation"
echo "════════════════════════════════════════"

for i in "${!EDITIONS[@]}"; do
  EDITION="${EDITIONS[$i]}"
  MANIFEST="${ROOT}/kde-neon-editions/${EDITION_DIRS[$i]}/manifests/${EDITION}.yaml"
  echo "--- ${EDITION} ---"
  if python3 "${SCRIPT_DIR}/validate-manifest.py" "${MANIFEST}"; then
    echo "    PASSED"
  else
    echo "    FAILED"
    ERRORS=$((ERRORS + 1))
  fi
done

# ── 2. shellcheck ─────────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════"
echo "  2. shellcheck"
echo "════════════════════════════════════════"

if ! command -v shellcheck &>/dev/null; then
  echo "WARNING: shellcheck not installed — skipping"
else
  find "${ROOT}/kde-neon-editions/ci-templates/scripts" -name "*.sh" ! -type l | sort | \
  while read -r SCRIPT; do
    echo "--- $(basename "${SCRIPT}") ---"
    if shellcheck --severity=warning --shell=bash "${SCRIPT}"; then
      echo "    PASSED"
    else
      ERRORS=$((ERRORS + 1))
    fi
  done
fi

# ── 3. GitLab CI YAML lint ────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════"
echo "  3. GitLab CI YAML lint"
echo "════════════════════════════════════════"

if [[ -z "${GITLAB_TOKEN:-}" ]]; then
  echo "WARNING: GITLAB_TOKEN not set — skipping CI YAML lint"
else
  CI_FILES=(
    "${ROOT}/kde-neon-editions/.gitlab-ci.yml"
    "${ROOT}/kde-neon-editions/neon-user/.gitlab-ci.yml"
    "${ROOT}/kde-neon-editions/neon-testing/.gitlab-ci.yml"
    "${ROOT}/kde-neon-editions/neon-developer-stable/.gitlab-ci.yml"
    "${ROOT}/kde-neon-editions/neon-developer-unstable/.gitlab-ci.yml"
  )

  for CI_FILE in "${CI_FILES[@]}"; do
    LABEL="$(basename "$(dirname "${CI_FILE}")")/.gitlab-ci.yml"
    echo "--- ${LABEL} ---"
    CONTENT=$(cat "${CI_FILE}")
    RESPONSE=$(curl -s \
      --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
      --header "Content-Type: application/json" \
      --request POST \
      "${CI_API_V4_URL}/ci/lint" \
      --data "{\"content\": $(python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' < "${CI_FILE}")}")

    STATUS=$(echo "${RESPONSE}" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
    if [[ "${STATUS}" == "valid" ]]; then
      echo "    PASSED"
    else
      echo "    FAILED"
      echo "${RESPONSE}" | grep -o '"errors":\[[^]]*\]' || echo "${RESPONSE}"
      ERRORS=$((ERRORS + 1))
    fi
  done
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════"
if [[ ${ERRORS} -eq 0 ]]; then
  echo "  All checks passed"
else
  echo "  ${ERRORS} check(s) failed"
fi
echo "════════════════════════════════════════"

exit ${ERRORS}
