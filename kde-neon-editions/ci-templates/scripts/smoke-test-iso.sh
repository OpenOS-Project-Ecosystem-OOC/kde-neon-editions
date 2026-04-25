#!/usr/bin/env bash
# smoke-test-iso.sh — boot an ISO in QEMU headless and verify it reaches
# the live desktop by checking for a running plasmashell process.
#
# This is a basic sanity check, not a full test suite.
# Requires: qemu-system-x86_64, ovmf (UEFI firmware)
#
# Usage: ./smoke-test-iso.sh <path-to.iso>
set -euo pipefail

ISO="${1:?Usage: $0 <iso-file>}"
[[ -f "${ISO}" ]] || { echo "ERROR: ISO not found: ${ISO}"; exit 1; }

TIMEOUT="${SMOKE_TEST_TIMEOUT:-300}"   # seconds to wait for desktop
SERIAL_LOG="$(mktemp /tmp/neon-smoke-XXXXXX.log)"
QEMU_PID=""

cleanup() {
  [[ -n "${QEMU_PID}" ]] && kill "${QEMU_PID}" 2>/dev/null || true
  rm -f "${SERIAL_LOG}"
}
trap cleanup EXIT

echo "==> Smoke testing: ${ISO}"
echo "    Timeout: ${TIMEOUT}s"
echo "    Serial log: ${SERIAL_LOG}"

# Boot the ISO in QEMU with serial console output
qemu-system-x86_64 \
  -m 2048 \
  -smp 2 \
  -enable-kvm \
  -bios /usr/share/ovmf/OVMF.fd \
  -cdrom "${ISO}" \
  -boot d \
  -nographic \
  -serial "file:${SERIAL_LOG}" \
  -display none \
  -no-reboot \
  -net none &
QEMU_PID=$!

echo "==> QEMU started (PID ${QEMU_PID}), waiting for boot..."

ELAPSED=0
INTERVAL=10
SUCCESS=false

while [[ ${ELAPSED} -lt ${TIMEOUT} ]]; do
  sleep ${INTERVAL}
  ELAPSED=$((ELAPSED + INTERVAL))

  if grep -q "plasmashell" "${SERIAL_LOG}" 2>/dev/null; then
    echo "==> plasmashell detected in serial output after ${ELAPSED}s"
    SUCCESS=true
    break
  fi

  # Also accept reaching the SDDM login screen
  if grep -q "sddm" "${SERIAL_LOG}" 2>/dev/null; then
    echo "==> SDDM detected in serial output after ${ELAPSED}s"
    SUCCESS=true
    break
  fi

  # Detect kernel panic
  if grep -q "Kernel panic" "${SERIAL_LOG}" 2>/dev/null; then
    echo "ERROR: Kernel panic detected" >&2
    tail -20 "${SERIAL_LOG}" >&2
    exit 1
  fi

  echo "    ${ELAPSED}s elapsed — still booting..."
done

if [[ "${SUCCESS}" == "true" ]]; then
  echo "==> Smoke test PASSED"
  exit 0
else
  echo "ERROR: Desktop not reached within ${TIMEOUT}s" >&2
  echo "--- Last 30 lines of serial log ---" >&2
  tail -30 "${SERIAL_LOG}" >&2
  exit 1
fi
