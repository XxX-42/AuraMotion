#!/bin/bash
set -euo pipefail

echo "==> Building AuraMotion in Release configuration..."
swift build -c release

APP_DIR="build/AuraMotion.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "==> Creating macOS Application Bundle at ${APP_DIR}..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

BIN_PATH="$(swift build -c release --show-bin-path)/AuraMotion"
cp "${BIN_PATH}" "${MACOS_DIR}/AuraMotion"
cp "Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"

SIGN_IDENTITY="${AURAMOTION_SIGN_IDENTITY:--}"
if [[ "${SIGN_IDENTITY}" == "-" ]]; then
    echo "==> Ad-hoc signing: rebuilding changes the app's TCC identity."
    echo "    Set AURAMOTION_SIGN_IDENTITY to a development certificate for stable privacy permissions."
fi
echo "==> Code signing application bundle..."
codesign -s "${SIGN_IDENTITY}" --force --deep --entitlements "Resources/AuraMotion.entitlements" "${APP_DIR}"

echo "==> Validation: Checking code signature..."
codesign --verify --deep --strict "${APP_DIR}"

echo "==> Build successful!"
echo "    Direct app launch: open ${APP_DIR}"
echo "    Finder/Terminal-backed launch: Start AuraMotion.command (in the project folder)"
