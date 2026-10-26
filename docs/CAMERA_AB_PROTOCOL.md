# Camera A/B verification protocol

Keep exports local. Every export must identify its source (`camera` versus `synthetic`) and settings. Do not interpret stationary statistics measured while moving as jitter.

1. Launch the installed signed bundle with `--cursor-experiments` to show Settings on first launch. Subsequent changes use the open Settings UI and never restart capture.
2. Select Baseline. Start the bounded camera recording. Hold the pointing pose comfortably still, with the hand fully visible and lighting unchanged. Then stop/export. Record usable sample count and tracking loss, not just elapsed time.
3. Replay this exact recorded landmark stream through Baseline and Optimized on the same display profile. Compute stationary pointer RMS, σx/σy, P95 displacement and max single-frame jump. Anchor statistics include indexTip, indexMCP, middleMCP, wrist, palm centroid and effective pointer anchor. Label camera observations separately from synthetic model tests.
4. Repeat runtime selection Baseline → Optimized → Baseline; toggle each module independently. Confirm effective configuration in diagnostics. Watch button release and first-frame displacement at transition. While a button is not held, move the physical mouse, pause, scroll, pinch and reacquire the hand. Any unknown observed behavior is a failed or unverified item, never a pass.
5. For ROI, use Vision full frame then ROI with the same camera, lighting, pose and duration; record inference percentiles, effective FPS, loss and ROI fallback. A changed scene is not a controlled comparison.
6. Sample process CPU over a timed interval and resident memory during each run. Report CPU convention and measurement duration; do not claim synthetic math timing is camera-to-cursor latency.
7. Target error, overshoot, slow-motion lag, cross-screen time and drag continuity require target-labelled tasks or known synthetic ground truth. Without those observations, export `unavailable` rather than zero. Human target acquisition cannot be inferred from unlabelled landmarks.
8. MediaPipe results exist only if a real provider is installed and inference ran. An unavailable optional module reports its reason, falls back to Vision and schedules no MediaPipe work.

The existing single latest-frame mailbox and single CGEvent output path stay active. Camera video is not recorded; only opt-in bounded landmark samples and numerical measurements are exported.
