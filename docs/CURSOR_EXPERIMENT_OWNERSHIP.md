# Cursor experiment integration

Upstream inspected 2026-10-27 (Asia/Shanghai): `main` / `16c46a54649a609da00ce3986293dda63d51598c`.
Working branch: `codex/cursor-experiments`. Existing deployed privacy/signing fixes retained separately in commit `8ffe61b`.
Hardware: MacBookAir10,1, Apple M1, 8 GB; macOS 27.2 (26B5086k).

Baseline `swift test --jobs 2`: 105 tests, 2 failures. Both are existing one-second camera lifecycle timeouts in `LifecycleTests`; the original compile and all gesture/filter tests completed. Raw log is saved outside the repository as `../baseline-swift-test.log`.

## Ownership

Each agent inspects before creating a feature branch and independent worktree. No agent edits main, another agent's checkout, or cherry-picks unfinished work. Only integration merges branches. At most three subagents can execute alongside the coordinator because this environment has four total agent slots.

| Agent | Owned production files | Owned tests |
| --- | --- | --- |
| A anchor | HandCursorFusion; optional new PointerAnchor helpers | PointerAnchorTests |
| B mapping | CursorController, CoordinateMapper, AppEnvironment; RelativePointerMapping | RelativePointerTests |
| C dynamics | New CursorDynamicsController and math helpers | CursorDynamicsTests |
| D filter | TimestampedOneEuroFilter; new filter configuration helper | FilterRuntimeTuningTests |
| E settings | AppSettings, SettingsRepository, SettingsView; experiment UI helper | ExperimentSettingsTests |
| F provider/ROI | VisionInferenceWorker; new HandPoseProvider, Vision/MediaPipe provider and ROI helpers | HandPoseProviderTests, VisionROITests |
| G metrics/regression | New bounded metrics/replay files, replay executable target, integration tests; existing regression tests only as needed | CursorExperimentRegressionTests; lifecycle test audit |
| H language (added by user) | Localization infrastructure, UI except SettingsView, human-readable domain labels | LocalizationTests |
| Integration | Common schema, adapters, conflict fixes, runtime metric hooks, final evidence/report | Combined checks |

## Shared contracts

`CursorExperimentSettings` is nested in existing AppSettings under `cursorExperiment`. All defaults are Baseline. `AppSettings.language` uses the shared AppLanguage enum added by H. Preset changes only experiment fields; individual controls make the experiment Custom.

- A: `HandCursorFusion.configure(strategy:)`, existing `update(_:)` and `reset()` remain.
- C: `CursorDynamicsController.init(settings:)`, `configure(_:)`, `reset(at:)`, `process(target:timestamp:phase:) -> CursorDynamicsResult?` (`point`, `speed`, `deadzone`, `gain`).
- B: `CursorController.reconfigure(_:cursorPosition:)`, `setInteractionState(_:currentCursor:)`, `freeze(at:)`, `rebase(to:)`, `lastDiagnostics`.
- F: `VisionInferenceWorker.reconfigure(_:completion:)` on its existing serial queue; no second mailbox or unbounded queue. Unavailable optional backend returns to Vision.
- E runtime: existing `AppEnvironment.updateSettings`; metrics calls `resetExperimentMetrics()` and `exportExperimentMetrics(completion:)` supplied at integration. No parallel persistence.

CGEvent output stays in EventOutputCoordinator/EventSynthesizer. GestureStateMachine semantics and production Vision remain authoritative. Baseline selection runs the original cursor path; all experimental computation is gated. Strategy changes must release synthetic buttons and freeze/rebase on the interaction queue.

Metrics must identify synthetic versus camera source. Unknown target accuracy and task timing are reported as unavailable unless target-labelled data was actually collected. An unavailable MediaPipe backend cannot produce fake benchmark samples.
