#!/usr/bin/env python3
"""Debug-only adapter: AuraMotion BGRA frames -> gaze_estimation preview/result.

The sibling repository is imported in its own Python environment. No webcam is
opened here; the caller supplies bounded camera frames and capture timestamps.
"""
import base64
import json
import hashlib
import os
from pathlib import Path
import struct
import sys
import time

repo = Path(os.environ["AURAMOTION_GAZE_ESTIMATION_DIR"])
sys.path.insert(0, str(repo))
import cv2
import numpy as np
from src.config import load_config
from src.headpose import estimate
from src.landmarks import LandmarkDetector
from src.normalize import normalize_observation


def read_exact(count):
    data = bytearray()
    while len(data) < count:
        part = sys.stdin.buffer.read(count - len(data))
        if not part:
            return None
        data.extend(part)
    return bytes(data)


def png(patch):
    ok, image = cv2.imencode('.png', patch)
    return base64.b64encode(image).decode('ascii') if ok else None


def checkpoint():
    explicit = os.environ.get('AURAMOTION_GAZE_ESTIMATION_MODEL')
    paths = [Path(explicit)] if explicit else list((repo / 'runs').glob('**/pretrained.pt'))
    # Auto-discover only completed, evaluated runs; never read a checkpoint
    # while the trainer is still writing or imply an unfinished model is ready.
    ready = [p for p in paths if p.is_file() and time.time() - p.stat().st_mtime > 5
             and (explicit or (p.parent / 'test_metrics.json').is_file())]
    return max(ready, key=lambda p: p.stat().st_mtime) if ready else None


def main():
    cfg = load_config()
    pipeline = None
    model_signature = None
    last_check = 0.0
    last_timestamp = 0
    with LandmarkDetector(cfg) as detector:
        while True:
            header = read_exact(24)
            if header is None:
                return
            frame_id, host_time, width, height = struct.unpack('>QdII', header)
            if not (0 < width <= 640 and 0 < height <= 640):
                return
            raw = read_exact(width * height * 4)
            if raw is None:
                return
            bgr = cv2.cvtColor(np.frombuffer(raw, np.uint8).reshape(height, width, 4), cv2.COLOR_BGRA2BGR)
            timestamp = max(last_timestamp + 1, time.monotonic_ns() // 1_000_000)
            last_timestamp = timestamp
            if pipeline is None and time.monotonic() - last_check > 5:
                last_check = time.monotonic()
                model = checkpoint()
                if model:
                    try:
                        import torch
                        from src.pipeline import GazePipeline
                        # Small single-frame CNN: avoid excessive CPU thread overhead.
                        torch.set_num_threads(1)
                        loaded_pipeline = GazePipeline(model, mode='geometric', cfg=cfg, smooth_angles=False)
                        digest = hashlib.sha256()
                        for path in (model, repo / 'config.yaml', repo / 'models/face_landmarker.task', repo / 'src/normalize.py', repo / 'src/headpose.py', repo / 'src/intrinsics.py', repo / 'src/landmarks.py', repo / 'src/geometry.py', repo / 'src/mpiigaze.py', repo / 'src/model.py', repo / 'src/pipeline.py'):
                            with path.open('rb') as source:
                                for chunk in iter(lambda: source.read(1024 * 1024), b''):
                                    digest.update(chunk)
                        import mediapipe
                        digest.update(str(mediapipe.__version__).encode('utf-8'))
                        model_signature = digest.hexdigest()
                        pipeline = loaded_pipeline
                    except Exception as error:
                        print(f'checkpoint load failed: {error}', file=sys.stderr, flush=True)
            obs = detector.detect(bgr, timestamp)
            response = {'frameID': frame_id, 'hostTime': host_time, 'phase': 'no_face',
                        'modelLoaded': pipeline is not None, 'modelSignature': model_signature, 'leftPatch': None,
                        'rightPatch': None, 'gaze': None, 'angles': None, 'eyeCenter': None, 'eyeRotation': None, 'screenGeometry': None, 'reason': obs.reason or ''}
            if obs.ok:
                normalized = None
                if pipeline is not None:
                    result = pipeline.process(bgr, obs)
                    response['reason'] = result.reason
                    normalized = result.normalized
                    # Normalized-eye-frame pitch/yaw, radians, directly from
                    # the CNN before projection, calibration or filtering.
                    if result.angles is not None and np.isfinite(result.angles).all():
                        response['angles'] = [float(result.angles[0]), float(result.angles[1])]
                        eye = normalized.image_left if normalized is not None else None
                        if eye is not None and np.isfinite(eye.eye_center_mm).all() and np.isfinite(eye.rotation).all():
                            response['eyeCenter'] = eye.eye_center_mm.tolist()
                            response['eyeRotation'] = eye.rotation.reshape(-1).tolist()
                            geometry = pipeline.geometry
                            response['screenGeometry'] = [geometry.width_mm, geometry.height_mm, geometry.offset_x_mm, geometry.offset_y_mm]
                    if result.angles is not None and normalized is not None:
                        # Upstream's default projection clamps to [-1, 1] before
                        # calibration. Preserve off-screen signal for fitting;
                        # the UI clips only the final displayed prediction.
                        from src.geometry import gaze_to_screen
                        from src.mpiigaze import angles_to_gaze
                        direction = angles_to_gaze(result.angles.reshape(1, 2))[0]
                        eye = normalized.image_left
                        point, reason = gaze_to_screen(
                            eye.eye_center_mm, eye.denormalize_direction(direction),
                            pipeline.geometry, clamp=False)
                        response['reason'] = reason
                        if point is not None and np.isfinite(point).all():
                            response.update(phase='uncalibrated_gaze', gaze=[float(point[0]), float(point[1])])
                if normalized is None:
                    pose = estimate(obs, cfg)
                    if pose is not None:
                        normalized = normalize_observation(bgr, obs, pose, cfg)
                if normalized is not None:
                    if normalized.ok:
                        response.update(leftPatch=png(normalized.image_left.patch),
                                        rightPatch=png(normalized.image_right.patch))
                        if response['phase'] == 'no_face':
                            response['phase'] = 'preview'
                    else:
                        response.update(phase='normalization_failed', reason=normalized.reason or '')
            print(json.dumps(response, separators=(',', ':'), allow_nan=False), flush=True)


if __name__ == '__main__':
    main()
