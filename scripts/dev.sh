#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$PROJECT_DIR"
MODE="${1:-run}"
if [[ "$MODE" != "run" && "$MODE" != "--build-only" ]]; then
    echo "Usage: ./scripts/dev.sh [--build-only]" >&2
    exit 2
fi

# A real signing identity keeps the designated requirement stable across builds.
SIGN_IDENTITY="${AURAMOTION_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
    IDENTITIES="$(security find-identity -v -p codesigning | sed -nE 's/^[[:space:]]*[0-9]+\) ([A-F0-9]{40}) "Apple Development:.*$/\1/p')"
    COUNT="$(printf '%s\n' "$IDENTITIES" | awk 'NF {n++} END {print n+0}')"
    if [[ "$COUNT" != 1 ]]; then
        echo "Expected one Apple Development signing identity; found $COUNT." >&2
        echo "Set AURAMOTION_SIGN_IDENTITY to a valid code-signing identity hash or name." >&2
        exit 1
    fi
    SIGN_IDENTITY="$IDENTITIES"
fi
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "A development signing identity is required for stable permissions; ad-hoc signing is not supported here." >&2
    exit 1
fi

echo "==> Incremental Debug build..."
swift build -c debug --product AuraMotion
BIN_PATH="$(swift build -c debug --show-bin-path)/AuraMotion"
APP_DIR="$PROJECT_DIR/build/AuraMotion Debug.app"
mkdir -p "$PROJECT_DIR/build"
STAGE_DIR="$(mktemp -d "$PROJECT_DIR/build/.auramotion-debug.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
STAGED_APP="$STAGE_DIR/AuraMotion Debug.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BIN_PATH" "$STAGED_APP/Contents/MacOS/AuraMotion"
cp Resources/Info.plist "$STAGED_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.ayush.AuraMotion.debug' "$STAGED_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName AuraMotion Pro Debug' "$STAGED_APP/Contents/Info.plist"
codesign --force --sign "$SIGN_IDENTITY" --entitlements Resources/AuraMotion.entitlements "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"

# Only stop this development bundle, never the separately installed release.
APP_EXECUTABLE="$APP_DIR/Contents/MacOS/AuraMotion"
while read -r pid command; do
    if [[ "$command" == "$APP_EXECUTABLE" ]]; then
        kill "$pid" 2>/dev/null || true
        for _ in {1..50}; do
            if ! kill -0 "$pid" 2>/dev/null; then break; fi
            sleep 0.1
        done
        if kill -0 "$pid" 2>/dev/null; then
            echo "Debug process $pid did not exit; bundle was not replaced." >&2
            exit 1
        fi
    fi
done < <(ps -axo pid=,comm=)
mkdir -p "$PROJECT_DIR/build"
rm -rf "$APP_DIR"
mv "$STAGED_APP" "$APP_DIR"
echo "==> Signed Debug app: $APP_DIR"
if [[ "$MODE" == "--build-only" ]]; then exit 0; fi

echo "==> Starting AuraMotion Pro Debug..."
AURAMOTION_FACE_PYTHON="$PROJECT_DIR/build/mediapipe-venv/bin/python" \
AURAMOTION_FACE_SCRIPT="$PROJECT_DIR/scripts/mediapipe_face_worker.py" \
AURAMOTION_FACE_MODEL="$PROJECT_DIR/build/mediapipe-models/face_landmarker.task" \
nohup "$APP_EXECUTABLE" > "$PROJECT_DIR/build/auramotion-debug.log" 2>&1 &
pid=$!
sleep 1
if ! kill -0 "$pid" 2>/dev/null; then
    echo "Debug app exited; see build/auramotion-debug.log" >&2
    exit 1
fi
echo "==> Running (PID $pid). Log: build/auramotion-debug.log"
