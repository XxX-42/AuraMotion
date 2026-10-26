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
        output_facial_transformation_matrixes=True,
    )
    with mp.tasks.vision.FaceLandmarker.create_from_options(options) as landmarker:
        last_timestamp = 0
        while True:
            header = read_exact(24)
            if header is None:
                return
            frame_id, host_time, width, height = struct.unpack('>QdII', header)
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
            points = [[p.x, p.y, p.z] for p in result.face_landmarks[0]] if result.face_landmarks else []
            matrix = result.facial_transformation_matrixes[0].tolist() if len(result.facial_transformation_matrixes) else None
            response = {"frameID": frame_id, "hostTime": host_time, "landmarks": points, "headTransform": matrix}
            print(json.dumps(response, separators=(',', ':'), allow_nan=False), flush=True)


if __name__ == '__main__':
    main()
