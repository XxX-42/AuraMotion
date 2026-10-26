# 2026-10-27 ROI sampling evidence

`recording-and-replay.json` contains the real hand landmark trace and the Baseline/Optimized offline replay. It contains hand pose data and no camera video. `summary.json` summarizes the recorded frame counts and metrics.

The recording uses Vision with ROI enabled and cursor optimizations disabled. The replay compares two cursor configurations on the same recorded trace; it is not a second live optimized run or a matched ROI-off trial. The stationary label is user-declared and cannot distinguish hand movement from tracking error.

The full test run recorded 168 passes and one camera lifecycle timeout while AuraMotion was running. The follow-up test log records that lifecycle test and five localization tests passing after AuraMotion was stopped.
