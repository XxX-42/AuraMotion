# Head-centered gaze regions (Debug MVP)

The Debug HUD draws the current face center, three boundaries (center, ring 1, ring 2), eight sectors and the candidate/focused wedge over the existing camera preview. Enable the camera preview and MediaPipe Face, open **视线校准**, and complete the existing nine-point calibration. Yellow indicates a candidate; cyan indicates a fixation-committed region. The region is unavailable without fresh, valid face and calibrated gaze. The overlay uses the camera-space face center and is only a visualization: screen gaze is never projected into camera coordinates.

`HeadReferenceProjector.debugApproximation` maps the camera normalized face bounding-box center to Quartz display coordinates and reverses source mirroring. This is a debug approximation, not a calibrated physical camera-to-display projection. The resolver compares that center with `GazeEstimate.screenPoint` in the same Quartz y-down coordinate system. Radii are fractions of the smaller display dimension (0.08, 0.20, 0.38); the overlay uses the same fractions of its smaller dimension for illustration. It does not drive the pointer or gesture actions. The existing fixation detector controls candidate/focused transitions; a stale region expires after 300 ms, and face/gaze time difference above 80 ms is rejected.

Diagnostics report existing Face FPS, the percentage of received face updates with a fresh gaze estimate since app launch, committed region switches, capture-to-region age P50/P95 for the last 300 valid samples, resolve time, and current Face/Gaze timestamp difference. Because current gaze is derived from the same face frame, the difference is normally zero; capture-to-region age is a different quantity. The numbers describe local debug processing, not eye-tracking accuracy.

Calibration is session-only. Head position, camera orientation, screen coordinates, glasses, lighting, and imperfect gaze estimates can affect both rings and sectors. Real head-centered selection and accuracy require the user's own nine-point calibration and visual verification; no artificial camera frame or synthetic test proves eye-direction accuracy.

## Initial user observation — 2026-10-27

After completing nine-point calibration, the user reported that region switching is accurate when the head remains near its calibration angle. When lowering the head or changing head position, looking in another direction with the eyes alone no longer produces accurate region switching. This is a qualitative report, not a measured angular-accuracy benchmark.

At a subsequent HUD snapshot, MediaPipe Face was active at 23.0 FPS, gaze availability was 40% since launch, the region switch counter was 31, and capture-to-region age P50/P95 was 59/82 ms. Fixation and the current region were unavailable at that instant. These aggregate metrics do not isolate the lowered-head condition and should not be interpreted as its accuracy or latency distribution.

Possible contributing factors include the uncalibrated camera-to-screen head-center approximation and the gaze model's limited calibration coverage for head-pose changes. The observation alone does not establish which is responsible; compare estimated gaze and projected head center separately before changing either algorithm.
