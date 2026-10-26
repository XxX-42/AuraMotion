#!/usr/bin/env python3
"""Debug-only MediaPipe face worker. Binary BGRA frames in, JSON lines out."""
import json
import struct
import sys
import time

import cv2
import mediapipe as mp
import numpy as np


def read_exact(n):
    chunks = bytearray()
    while len(chunks) < n:
        part = sys.stdin.buffer.read(n - len(chunks))
        if not part:
            return None
        chunks.extend(part)
    return bytes(chunks)


def main():
    options = mp.tasks.vision.FaceLandmarkerOptions(
        base_options=mp.tasks.BaseOptions(model_asset_path=sys.argv[1]),
        running_mode=mp.tasks.vision.RunningMode.VIDEO,
        num_faces=1,
    )
    with mp.tasks.vision.FaceLandmarker.create_from_options(options) as landmarker:
        last_timestamp = 0
        while True:
            header = read_exact(8)
            if header is None:
                return
            width, height = struct.unpack('>II', header)
            if not (0 < width <= 320 and 0 < height <= 320):
                return
            frame = read_exact(width * height * 4)
            if frame is None:
                return
            bgra = np.frombuffer(frame, np.uint8).reshape((height, width, 4))
            rgb = cv2.cvtColor(bgra, cv2.COLOR_BGRA2RGB)
            timestamp = max(last_timestamp + 1, time.monotonic_ns() // 1_000_000)
            last_timestamp = timestamp
            result = landmarker.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb), timestamp)
            points = [[round(p.x, 5), round(p.y, 5)] for p in result.face_landmarks[0]] if result.face_landmarks else []
            print(json.dumps(points, separators=(',', ':')), flush=True)


if __name__ == '__main__':
    main()
