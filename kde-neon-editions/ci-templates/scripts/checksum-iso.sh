#!/usr/bin/env bash
# checksum-iso.sh — generate SHA256 checksums and GPG signatures for built ISOs.
#
# Optional environment variables:
#   GPG_SIGNING_KEY   — fingerprint of the key to sign with
#                       (set as a masked CI/CD variable)
#   GPG_PRIVATE_KEY   — armored private key exported via:
#                         gpg --armor --export-secret-keys <fingerprint>
#                       (set as a file-type CI/CD variable)
set -euo pipefail

echo "==> Generating checksums"
for ISO in *.iso; do
  [[ -f "${ISO}" ]] || { echo "No ISO files found."; exit 0; }
  sha256sum "${ISO}" > "${ISO}.sha256"
  echo "    ${ISO}.sha256"
done

# Sign if a key is available
if [[ -n "${GPG_SIGNING_KEY:-}" && -n "${GPG_PRIVATE_KEY:-}" ]]; then
  echo "==> Importing signing key"
  echo "${GPG_PRIVATE_KEY}" | gpg --batch --import

  for ISO in *.iso; do
    [[ -f "${ISO}" ]] || continue
    echo "==> Signing: ${ISO}"
    gpg --batch --yes \
      --local-user "${GPG_SIGNING_KEY}" \
      --detach-sign --armor \
      --output "${ISO}.sig" \
      "${ISO}"
    echo "    ${ISO}.sig"
  done
else
  echo "INFO: GPG_SIGNING_KEY / GPG_PRIVATE_KEY not set — skipping signatures"
fi
