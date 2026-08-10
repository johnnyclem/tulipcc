#!/usr/bin/env bash
# Build a double-clickable AMYboard Starter.app for macOS.
set -euo pipefail
cd "$(dirname "$0")"

BIN_NAME="AMYboardStarter"
DIST="dist"
APP_DIR="${DIST}/AMYboard Starter.app"

echo "Building ${BIN_NAME} (release)..."
swift build -c release --product "${BIN_NAME}"

BIN_PATH="$(swift build -c release --show-bin-path)/${BIN_NAME}"
if [[ ! -x "${BIN_PATH}" ]]; then
  echo "error: binary not found at ${BIN_PATH}" >&2
  exit 1
fi

echo "Assembling ${APP_DIR}..."
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${BIN_PATH}" "${APP_DIR}/Contents/MacOS/${BIN_NAME}"
cp Info.plist "${APP_DIR}/Contents/Info.plist"

# Ad-hoc sign so Gatekeeper is slightly less grumpy on the same machine.
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null || true
fi

echo
echo "Done: ${APP_DIR}"
echo "Open it with:  open \"${APP_DIR}\""
echo
echo "To give to a friend: zip the .app and send it."
echo "  First launch on their Mac: right-click -> Open (if macOS blocks unsigned apps)."
