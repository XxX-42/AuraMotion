#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd)"
REPO="${AURAMOTION_GAZE_ESTIMATION_DIR:-$(cd -- "$PROJECT_DIR/.." && pwd)/gaze_estimation}"
UV="${REPO}/.bootstrap/bin/uv"
if [[ ! -x "$UV" ]]; then UV="$(command -v uv || true)"; fi
if [[ -z "$UV" || ! -x "${REPO}/.venv/bin/python" ]]; then
    echo "Need uv and the existing gaze_estimation Python 3.11 environment: ${REPO}/.venv" >&2
    exit 1
fi
# MediaPipe 1.0.1's macOS wheel crashes in this runtime. Install a separate
# override without modifying the sibling project's pinned virtual environment.
"$UV" pip install --python "${REPO}/.venv/bin/python" --target "${PROJECT_DIR}/build/gaze-estimation-mp-override" --no-deps 'mediapipe==1.1.1'
