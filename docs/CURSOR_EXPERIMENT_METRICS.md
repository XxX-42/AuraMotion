# Cursor experiment metrics and replay

## Recording

`CursorExperimentMetricsRecorder` is opt-in and keeps a fixed-capacity ring in memory. Its default capacity is 1,800 frames; the maximum is 3,600. Recording duration is bounded to 300 seconds. It does not write files, create a worker, or retain image buffers. Each `CursorExperimentFrame` requires a monotonic host-time timestamp and a `camera` or `synthetic` source label. Frames can include normalized `HandSample` landmarks, gesture state, inference and mailbox timings, cumulative mailbox drops, ROI/fallback metadata, copied controller diagnostics, and optional ground-truth task annotations. Camera recordings can declare a whole-session purpose such as stationary hold, slow movement, or fast movement; this labels phase statistics only and never supplies target coordinates.

The AppEnvironment hook should call `record(frame:)` on the existing interaction queue only while recording. A copied snapshot can be evaluated and exported on a separate queue with `CursorExperimentMetricsExporter.writeBundle(_:to:)`. That JSON document contains the recorded landmarks and camera/provider metadata plus baseline and optimized replay rows and summaries. `reset()` releases buffered frame memory.

## Replay

`CursorExperimentReplayEvaluator.evaluate(_:)` feeds the exact same saved `HandSample` trace to the existing `CursorController` twice: once with default Baseline settings and once after `applyPreset(.optimized)`. It does not include a second cursor engine. CSV includes the monotonic `timestamp`, source, mode, raw anchor, filtered point, cursor output, speed, deadzone, gain, and recorded interaction state.

```sh
swift run CursorReplay --synthetic --output /tmp/cursor-replay.csv
swift run CursorReplay --synthetic --sweep --output /tmp/cursor-replay-sweep.json
swift run CursorReplay --input /path/to/recording.json --output /tmp/replay.json
swift run CursorReplay --input /path/to/old-session.json --source camera --output /tmp/replay.csv
```

Old `LandmarkRecorder` session files did not store a source; the CLI therefore requires an explicit `--source` for them. New recordings and live export bundles carry their source and can be replayed directly. JSON report output includes metric units and reasons for unavailable values; the live bundle additionally includes the original trace.

`--sweep` replays one trace as Baseline, stable-anchor plus relative mapping, those features plus optimized filtering/drag tuning/quantization, the same set plus adaptive deadzone, the six-module Optimized preset, and the full seven-module variant with velocity gain enabled. The Optimized preset leaves velocity gain off because the deterministic ablation produced substantially worse target and slow-movement errors with gain enabled. It remains an independent toggle for custom evaluation. Standard camera A/B bundles still contain only Baseline and Optimized.

## Interpretation

- Effective FPS is computed from the recorded frame timestamps. Synthetic FPS is the generated trace cadence, not measured camera performance.
- Inference and mailbox percentiles are null with an explanation when timing samples were not collected. Synthetic traces deliberately contain no simulated inference timings.
- Joint and pointer sigma/displacement describe all valid observations. Stationary statistics additionally require a current sample and a valid pointer-active state/anchor. Inactive or tracking-lost frames do not count as zero movement; phase changes, identity changes, and long gaps split the stationary segments so transitions do not inflate the step metrics.
- `trackingLossTransitionCount` counts transitions into the captured `trackingLost` interaction state. It is not inferred from missing landmarks.
- Target error, overshoot percentiles, slow-movement lag, fast-target completion, click-position error, and drag continuity require explicit target/task annotations. A camera trace without those labels reports unavailable reasons instead of zero.
- CPU and resident memory require an external process sampler such as `scripts/measure_process.py` during the run. Replay does not estimate or fabricate them.
- Synthetic traces are deterministic checks of controller behavior and metric calculations. Their target path is aligned to the legacy pointer anchor and both controller runs start at the same screen point. They are not camera results or user-performance claims.
