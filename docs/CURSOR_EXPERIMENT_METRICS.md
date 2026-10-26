# Cursor experiment metrics and replay

## Recording

`CursorExperimentMetricsRecorder` is opt-in and keeps a fixed-capacity ring in memory. Its default capacity is 1,800 frames; the maximum is 3,600. Recording duration is bounded to 300 seconds. It does not write files, create a worker, or retain image buffers. Each `CursorExperimentFrame` requires a monotonic host-time timestamp and a `camera` or `synthetic` source label. Frames can include normalized `HandSample` landmarks, gesture state, inference and mailbox timings, cumulative mailbox drops, ROI/fallback metadata, copied controller diagnostics, and optional ground-truth task annotations.

The AppEnvironment hook should call `record(frame:)` on the existing interaction queue only while recording. A copied snapshot can be evaluated and exported on a separate queue with `CursorExperimentMetricsExporter.writeBundle(_:to:)`. That JSON document contains the recorded landmarks and camera/provider metadata plus baseline and optimized replay rows and summaries. `reset()` releases buffered frame memory.

## Replay

`CursorExperimentReplayEvaluator.evaluate(_:)` feeds the exact same saved `HandSample` trace to the existing `CursorController` twice: once with default Baseline settings and once after `applyPreset(.optimized)`. It does not include a second cursor engine. CSV includes the monotonic `timestamp`, source, mode, raw anchor, filtered point, cursor output, speed, deadzone, gain, and recorded interaction state.

```sh
swift run CursorReplay --synthetic --output /tmp/cursor-replay.csv
swift run CursorReplay --input /path/to/recording.json --output /tmp/replay.json
swift run CursorReplay --input /path/to/old-session.json --source camera --output /tmp/replay.csv
```

Old `LandmarkRecorder` session files did not store a source; the CLI therefore requires an explicit `--source` for them. New recordings carry their source. JSON report output includes metric units and reasons for unavailable values; the live bundle additionally includes the original trace.

## Interpretation

- Effective FPS is computed from the recorded frame timestamps. Synthetic FPS is the generated trace cadence, not measured camera performance.
- Inference and mailbox percentiles are null with an explanation when timing samples were not collected. Synthetic traces deliberately contain no simulated inference timings.
- Joint and pointer sigma/displacement describe all valid observations. The separately reported stationary subset is populated only for frames explicitly annotated `stationary`; movement is never labeled jitter by inference.
- Target error, overshoot percentiles, slow-movement lag, fast-target completion, click-position error, and drag continuity require explicit target/task annotations. A camera trace without those labels reports unavailable reasons instead of zero.
- CPU and resident memory require an external process sampler such as `scripts/measure_process.py` during the run. Replay does not estimate or fabricate them.
- Synthetic traces are deterministic checks of controller behavior and metric calculations. They are not camera results or user-performance claims.
