#!/usr/bin/env bash
# sync-upstream.sh — pull latest commits from invent.kde.org/neon into a
# tracking branch in this repo.
#
# Required environment variables:
#   UPSTREAM_REPO_URL   — e.g. https://invent.kde.org/neon/neon/seeds.git
#   UPSTREAM_BRANCH     — e.g. Neon/release
#   CI_PROJECT_URL      — set automatically by GitLab CI
#   GITLAB_TOKEN        — project access token with write_repository scope
#                         (set as a masked CI/CD variable, never in source)
set -euo pipefail

: "${UPSTREAM_REPO_URL:?UPSTREAM_REPO_URL must be set}"
: "${UPSTREAM_BRANCH:?UPSTREAM_BRANCH must be set}"
: "${GITLAB_TOKEN:?GITLAB_TOKEN must be set (masked CI/CD variable)}"
: "${CI_PROJECT_URL:?CI_PROJECT_URL must be set}"

TRACKING_BRANCH="upstream/${UPSTREAM_BRANCH}"

echo "==> Fetching ${UPSTREAM_BRANCH} from ${UPSTREAM_REPO_URL}"
git remote add upstream "${UPSTREAM_REPO_URL}" 2>/dev/null || \
  git remote set-url upstream "${UPSTREAM_REPO_URL}"

git fetch upstream "${UPSTREAM_BRANCH}" --depth=50

echo "==> Updating tracking branch: ${TRACKING_BRANCH}"
git checkout -B "${TRACKING_BRANCH}" FETCH_HEAD

# Push back to origin using the token for auth
ORIGIN_URL="${CI_PROJECT_URL/https:\/\//https://gitlab-ci-token:${GITLAB_TOKEN}@}"
git push "${ORIGIN_URL}" "${TRACKING_BRANCH}" --force

echo "==> Sync complete: ${TRACKING_BRANCH} updated"
