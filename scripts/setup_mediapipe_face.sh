#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PYTHON="${AURAMOTION_PYTHON:-/opt/homebrew/bin/python3.12}"
if [[ ! -x "$PYTHON" ]]; then
    echo "Python 3.12 not found; set AURAMOTION_PYTHON to a compatible Python." >&2
    exit 1
fi
mkdir -p build/mediapipe-models
"$PYTHON" -m venv build/mediapipe-venv
build/mediapipe-venv/bin/pip install 'mediapipe==1.1.1'
curl -fL --retry 2 -o build/mediapipe-models/face_landmarker.task https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/latest/face_landmarker.task
