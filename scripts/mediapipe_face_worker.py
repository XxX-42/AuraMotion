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
        benchmark_landmarker = None
        last_timestamp = 0
        while True:
            header = read_exact(28)
            if header is None:
                return
            frame_id, host_time, width, height, benchmark = struct.unpack('>QdIII', header)
            if benchmark not in (0, 1) or not (0 < width <= 640 and 0 < height <= 640):
                return
            frame = read_exact(width * height * 4)
            if frame is None:
                return
            bgra = np.frombuffer(frame, np.uint8).reshape((height, width, 4))
            rgb = cv2.cvtColor(bgra, cv2.COLOR_BGRA2RGB)
            small_scale = min(1.0, 320 / max(width, height))
            small = cv2.resize(rgb, (max(1, round(width * small_scale)), max(1, round(height * small_scale))), interpolation=cv2.INTER_AREA) if small_scale < 1 else rgb
            timestamp = max(last_timestamp + 1, time.monotonic_ns() // 1_000_000)
            last_timestamp = timestamp
            started = time.perf_counter()
            result = landmarker.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=small), timestamp)
            ms320 = (time.perf_counter() - started) * 1000
            points = [[p.x, p.y, p.z] for p in result.face_landmarks[0]] if result.face_landmarks else []
            matrix = result.facial_transformation_matrixes[0].tolist() if len(result.facial_transformation_matrixes) else None
            response = {"frameID": frame_id, "hostTime": host_time, "landmarks": points, "headTransform": matrix}
            if benchmark:
                if benchmark_landmarker is None:
                    benchmark_landmarker = mp.tasks.vision.FaceLandmarker.create_from_options(options)
                started = time.perf_counter()
                large_result = benchmark_landmarker.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb), timestamp)
                ms640 = (time.perf_counter() - started) * 1000
                large_points = [[p.x, p.y, p.z] for p in large_result.face_landmarks[0]] if large_result.face_landmarks else []
                large_matrix = large_result.facial_transformation_matrixes[0].tolist() if len(large_result.facial_transformation_matrixes) else None
                response["benchmark640"] = {"frameID": frame_id, "hostTime": host_time, "landmarks": large_points, "headTransform": large_matrix}
                response["benchmarkTiming"] = {"ms320": ms320, "ms640": ms640, "width": width, "height": height}
            print(json.dumps(response, separators=(',', ':'), allow_nan=False), flush=True)


if __name__ == '__main__':
    main()
