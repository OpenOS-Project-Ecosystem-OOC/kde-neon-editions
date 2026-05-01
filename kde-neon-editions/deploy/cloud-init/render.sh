#!/usr/bin/env sh
# render.sh — substitute tokens into user-data.yaml and print to stdout.
#
# Usage:
#   GITLAB_RUNNER_TOKEN="glrt-..." RUNNER_NAME="my-builder" \
#     bash deploy/cloud-init/render.sh > /tmp/user-data.yaml
#
# Then pass /tmp/user-data.yaml as --user-data to your cloud provider CLI.
set -e

: "${GITLAB_RUNNER_TOKEN:?GITLAB_RUNNER_TOKEN must be set}"

RUNNER_NAME="${RUNNER_NAME:-$(hostname)-iso-builder}"
GITLAB_URL="${GITLAB_URL:-https://gitlab.com}"
RUNNER_CONCURRENT="${RUNNER_CONCURRENT:-1}"
RUNNER_TAGS="${RUNNER_TAGS:-privileged,iso-builder,neon}"

TEMPLATE="$(dirname "$0")/user-data.yaml"
[ -f "${TEMPLATE}" ] || { echo "ERROR: ${TEMPLATE} not found" >&2; exit 1; }

sed \
  -e "s|@@GITLAB_RUNNER_TOKEN@@|${GITLAB_RUNNER_TOKEN}|g" \
  -e "s|@@RUNNER_NAME@@|${RUNNER_NAME}|g" \
  -e "s|@@GITLAB_URL@@|${GITLAB_URL}|g" \
  -e "s|@@RUNNER_CONCURRENT@@|${RUNNER_CONCURRENT}|g" \
  -e "s|@@RUNNER_TAGS@@|${RUNNER_TAGS}|g" \
  "${TEMPLATE}"
