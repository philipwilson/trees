# Project Review

## Findings

1. **High**: Pending watch queue is never persisted after being cleared, so previously queued trees can be resent repeatedly on later activations (duplicate imports on iPhone). (`Shared/WatchConnectivityManager.swift:60`, `Shared/WatchConnectivityManager.swift:64`, `Shared/WatchConnectivityManager.swift:71`, `Shared/WatchConnectivityManager.swift:76`, `Shared/WatchConnectivityManager.swift:95`)

2. **High**: Import paths preserve incoming `id` values without collision handling, while duplicate deletion is keyed by `UUID`; importing the same export twice can make one selection/delete operation remove multiple records sharing the same `id` (including both copies). (`Trees/Views/ImportTreesView.swift:141`, `Trees/Views/ImportCollectionView.swift:133`, `Trees/Views/DuplicateTreesView.swift:10`, `Trees/Views/DuplicateTreesView.swift:182`)

3. **High**: Photo capture can crash on devices where camera source type is unavailable (not gated before presenting `UIImagePickerController`), and this app enables Mac Catalyst. (`Trees/Views/Components/ImagePicker.swift:11`, `Trees/Views/Components/ImagePicker.swift:57`, `project.yml:58`)

4. **Medium**: `ImportTreesView` reports success even when initial save fails, and delayed photo-save errors are swallowed; users can get a success message for partially/unsaved imports. (`Trees/Views/ImportTreesView.swift:190`, `Trees/Views/ImportTreesView.swift:192`, `Trees/Views/ImportTreesView.swift:206`, `Trees/Views/ImportTreesView.swift:221`)

5. **Low**: iPad left-landscape orientation value is misspelled, so that orientation may not be honored. (`Trees/Info.plist:52`, `project.yml:44`)

6. **Medium (testing gap)**: No test targets are defined in the project file, so critical import/sync/data-loss paths are unguarded by automated tests. (`project.yml:16`, `project.yml:17`, `project.yml:74`, `project.yml:113`)

## Open Questions / Assumptions

1. Is imported `id` intended to be globally stable across repeated imports? If yes, imports should dedupe/update existing rows rather than insert blindly.
2. For watch sync, is delivery intended to be at-least-once or exactly-once? Current queue persistence behavior is inconsistent with both.

## Validation Gaps

1. Full clean build validation was limited in this environment because `actool` failed with missing `watchsimulator` runtimes during `xcodebuild`.
2. No automated tests were available to execute.
