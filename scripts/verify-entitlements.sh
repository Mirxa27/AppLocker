#!/usr/bin/env bash
# Fails fast if entitlements plists were corrupted to an empty <dict/>
# (common editor/merge glitch; causes App Store rejection + runtime issues).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export APPLOCKER_REPO_ROOT="$ROOT"
python3 <<'PY'
import os
import plistlib
import sys
from pathlib import Path

root = Path(os.environ["APPLOCKER_REPO_ROOT"])
files = [
    root / "SupportingFiles/macOS/AppLocker.entitlements",
    root / "SupportingFiles/iOS/AppLockerCompanion.entitlements",
]

def check(path: Path, min_keys: int, required: set[str]) -> None:
    raw = path.read_bytes()
    data = plistlib.loads(raw)
    if not isinstance(data, dict):
        print(f"FAIL: {path} root is not a dict", file=sys.stderr)
        sys.exit(1)
    keys = set(data.keys())
    if len(keys) < min_keys:
        print(f"FAIL: {path} has only {len(keys)} entitlement keys (expected at least {min_keys}).", file=sys.stderr)
        print("Restore from git: git checkout HEAD -- <path>", file=sys.stderr)
        sys.exit(1)
    missing = required - keys
    if missing:
        print(f"FAIL: {path} missing required keys: {sorted(missing)}", file=sys.stderr)
        sys.exit(1)
    print(f"OK: {path.name} ({len(keys)} keys)")

check(
    root / "SupportingFiles/macOS/AppLocker.entitlements",
    min_keys=5,
    required={"com.apple.security.app-sandbox", "com.apple.developer.icloud-services"},
)
check(
    root / "SupportingFiles/iOS/AppLockerCompanion.entitlements",
    min_keys=4,
    required={"com.apple.developer.icloud-services"},
)
print("Entitlements verification passed.")
PY
