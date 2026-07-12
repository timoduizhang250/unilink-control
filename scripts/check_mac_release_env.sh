#!/usr/bin/env bash
set -euo pipefail

missing=0

need() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "missing: $name"
    missing=1
  else
    echo "ok: $name ($(command -v "$name"))"
  fi
}

echo "== UniLink macOS release environment =="
sw_vers || true
uname -m

need git
need clang
need python3
need rustc
need cargo
need flutter
need hdiutil

if [ ! -d /Applications/Xcode.app ]; then
  echo "missing: /Applications/Xcode.app"
  missing=1
else
  echo "ok: /Applications/Xcode.app"
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "missing: usable xcodebuild (full Xcode must be selected)"
  missing=1
else
  xcodebuild -version
fi

if [ "$missing" -ne 0 ]; then
  echo
  echo "Mac release build is not ready."
  echo "Install full Xcode, select it with sudo xcode-select -s /Applications/Xcode.app/Contents/Developer, then install Rust and Flutter."
  exit 1
fi

echo
echo "Mac release build environment is ready."
