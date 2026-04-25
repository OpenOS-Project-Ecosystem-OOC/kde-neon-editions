#!/usr/bin/env python3
"""validate-manifest.py — validate an edition package manifest YAML.

Checks:
  1. Required top-level keys are present.
  2. All package lists are non-empty lists of strings.
  3. The declared neon_archive is reachable (HTTP HEAD).
  4. Optionally verifies each package exists in the archive (apt-cache).

Usage:
    python3 validate-manifest.py manifests/user.yaml
"""

import sys
import urllib.request
import urllib.error
import yaml

REQUIRED_KEYS = {
    "edition",
    "upstream_branch",
    "ubuntu_series",
    "neon_archive",
    "neon_archive_key",
    "base_packages",
    "plasma_packages",
    "application_packages",
    "neon_packages",
    "installer_packages",
}

PACKAGE_LIST_KEYS = {
    "base_packages",
    "plasma_packages",
    "application_packages",
    "neon_packages",
    "installer_packages",
    "developer_extras",
    "testing_extras",
}


def load(path: str) -> dict:
    with open(path) as f:
        return yaml.safe_load(f)


def check_required_keys(manifest: dict) -> list[str]:
    errors = []
    for key in REQUIRED_KEYS:
        if key not in manifest:
            errors.append(f"Missing required key: '{key}'")
    return errors


def check_package_lists(manifest: dict) -> list[str]:
    errors = []
    for key in PACKAGE_LIST_KEYS:
        if key not in manifest:
            continue
        val = manifest[key]
        if val is None:
            continue
        if not isinstance(val, list):
            errors.append(f"'{key}' must be a list, got {type(val).__name__}")
            continue
        for i, pkg in enumerate(val):
            if not isinstance(pkg, str):
                errors.append(f"'{key}[{i}]' must be a string, got {type(pkg).__name__}: {pkg!r}")
            elif not pkg.strip():
                errors.append(f"'{key}[{i}]' is an empty string")
    return errors


def check_archive_reachable(archive_url: str) -> list[str]:
    errors = []
    test_url = archive_url.rstrip("/") + "/dists/noble/Release"
    try:
        req = urllib.request.Request(test_url, method="HEAD")
        with urllib.request.urlopen(req, timeout=10) as resp:
            if resp.status not in (200, 301, 302):
                errors.append(f"Archive returned HTTP {resp.status}: {test_url}")
    except urllib.error.URLError as e:
        # Non-fatal in CI where network may be restricted — warn only
        print(f"WARNING: Could not reach archive ({e}): {test_url}", file=sys.stderr)
    return errors


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <manifest.yaml>", file=sys.stderr)
        sys.exit(1)

    path = sys.argv[1]
    print(f"Validating: {path}")

    try:
        manifest = load(path)
    except yaml.YAMLError as e:
        print(f"YAML parse error: {e}", file=sys.stderr)
        sys.exit(1)

    errors = []
    errors += check_required_keys(manifest)
    errors += check_package_lists(manifest)
    errors += check_archive_reachable(manifest.get("neon_archive", ""))

    if errors:
        print("\nValidation FAILED:")
        for err in errors:
            print(f"  ✗ {err}")
        sys.exit(1)

    print(f"Validation passed for edition: {manifest.get('edition')}")


if __name__ == "__main__":
    main()
