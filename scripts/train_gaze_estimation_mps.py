#!/usr/bin/env python3
"""Run the sibling project's existing pretraining entry point using macOS MPS.

The upstream script selects only CUDA or CPU. This launcher changes only the
local execution device and DataLoader workers, without editing the sibling
checkout. Model, dataset, split, loss and evaluation remain upstream's.
"""
from pathlib import Path
import os
import sys

def main():
    repo = Path(os.environ.get('AURAMOTION_GAZE_ESTIMATION_DIR', Path(__file__).resolve().parents[2] / 'gaze_estimation'))
    sys.path.insert(0, str(repo))
    source_path = repo / 'src/pretrain.py'
    source = source_path.read_text()
    old = 'device = "cuda" if torch.cuda.is_available() else "cpu"'
    new = 'device = "cuda" if torch.cuda.is_available() else ("mps" if torch.backends.mps.is_available() else "cpu")'
    if source.count(old) != 1:
        raise RuntimeError('Upstream pretraining device selection changed; inspect it before running this launcher.')
    old_workers = 'num_workers=4'
    old_persistent = 'persistent_workers=True'
    if source.count(old_workers) != 1 or source.count(old_persistent) != 1:
        raise RuntimeError('Upstream DataLoader configuration changed; inspect it before running this launcher.')
    source = source.replace(old, new).replace(old_workers, 'num_workers=0').replace(old_persistent, 'persistent_workers=False')
    namespace = {'__name__': '__main__', '__package__': 'src', '__file__': str(source_path)}
    exec(compile(source, str(source_path), 'exec'), namespace)


if __name__ == "__main__":
    main()
