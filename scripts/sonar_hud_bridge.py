#!/usr/bin/env python3
"""Run the existing sonar implementation without starting its web UI."""
import importlib.util
import json
import os
import sys
import threading
import time

module_path, output_path = sys.argv[1:3]
spec = importlib.util.spec_from_file_location('acoustic_sonar', module_path)
sonar = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sonar)
threading.Thread(target=sonar.sense_loop, daemon=True).start()
while True:
    with sonar._cache_lock:
        data = {key: sonar._cache.get(key) for key in ('distance_m', 'status', 'timestamp', 'mic_rms')}
    temp = output_path + '.tmp'
    with open(temp, 'w', encoding='utf-8') as stream:
        json.dump(data, stream, allow_nan=False)
    os.replace(temp, output_path)
    time.sleep(0.25)
