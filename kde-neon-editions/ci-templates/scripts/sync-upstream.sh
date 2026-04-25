#!/usr/bin/env bash
# sync-upstream.sh — pull latest commits from kde-groups/neon into a
# tracking branch in this repo.
#
# Source repos live at:
#   gitlab.com/openos-project/kde-ecosystem-deving/kde-groups/neon
#
# Uses CI_JOB_TOKEN to fetch from the internal GitLab group (no PAT needed).
# Uses GITLAB_TOKEN only for pushing the tracking branch back to origin.
#
# Required environment variables:
#   UPSTREAM_REPO_URL   — e.g. https://gitlab.com/openos-project/kde-ecosystem-deving/kde-groups/neon/neon/seeds.git
#   UPSTREAM_BRANCH     — e.g. Neon/release
#   CI_PROJECT_URL      — set automatically by GitLab CI
#   CI_JOB_TOKEN        — set automatically by GitLab CI (used for fetch)
#   GITLAB_TOKEN        — project access token with write_repository scope
#                         (set as a masked CI/CD variable, used for push)
set -euo pipefail

: "${UPSTREAM_REPO_URL:?UPSTREAM_REPO_URL must be set}"
: "${UPSTREAM_BRANCH:?UPSTREAM_BRANCH must be set}"
: "${CI_PROJECT_URL:?CI_PROJECT_URL must be set}"

TRACKING_BRANCH="upstream/${UPSTREAM_BRANCH}"

# Build authenticated fetch URL using CI_JOB_TOKEN (works for any repo on
# the same GitLab instance without needing a separate PAT)
if [[ -n "${CI_JOB_TOKEN:-}" ]]; then
  # Strip protocol and inject token
  FETCH_URL="${UPSTREAM_REPO_URL/https:\/\//https://gitlab-ci-token:${CI_JOB_TOKEN}@}"
else
  # Local/manual run — use URL as-is (requires SSH key or credential helper)
  FETCH_URL="${UPSTREAM_REPO_URL}"
fi

echo "==> Fetching ${UPSTREAM_BRANCH} from kde-groups/neon"
git remote add upstream "${FETCH_URL}" 2>/dev/null || \
  git remote set-url upstream "${FETCH_URL}"

git fetch upstream "${UPSTREAM_BRANCH}" --depth=50

echo "==> Updating tracking branch: ${TRACKING_BRANCH}"
git checkout -B "${TRACKING_BRANCH}" FETCH_HEAD

# Push back to origin — requires GITLAB_TOKEN with write_repository scope
: "${GITLAB_TOKEN:?GITLAB_TOKEN must be set (masked CI/CD variable)}"
ORIGIN_URL="${CI_PROJECT_URL/https:\/\//https://gitlab-ci-token:${GITLAB_TOKEN}@}"
git push "${ORIGIN_URL}" "${TRACKING_BRANCH}" --force

echo "==> Sync complete: ${TRACKING_BRANCH} updated"
