# Trees Codebase Review — Bugs, Architecture, and Feature Opportunities

Date: 2026-06-10
Scope: full source review — models/sync layer, export/import system, iPhone views/components, watch app + widget, iPad views, project configuration. Follows up on `RECOMMENDATIONS_2026-02-17.md`.

## Status of the 2026-02-17 recommendations

Fixed since February: camera availability guard (ImagePicker), save-failure rollback + alert in CaptureTreeView, AddNoteView now saves explicitly, the `Landscage` orientation typo, indefinite `startUpdatingLocation()` in the map views, and `OutputStream.write` return values are now checked in JSONExporter.

Still outstanding: duplicated import models/logic between ImportTreesView and ImportCollectionView (#7), per-tree fetch/save in WatchTreeImporter (#8), weak thumbnail cache key (#10, see M-9 below), and no test targets (#11, see C-7 below). Export work moved from `Task.detached` to `Task {}` (#1), which fixed the actor-safety issue but introduced a new one: the whole export now blocks the main thread (M-1 below).

Note: the uncommitted "Get Directions" button in `TreeDetailView.swift` was reviewed and is fine as-is (one nit: `tree.species` may want the same `displayName`-style fallback used elsewhere if species is whitespace).

---

## Critical / High

### C-1. Stale cached GPS fixes are accepted as the tree location (iPhone + watch)
`Trees/Services/LocationManager.swift:54-57`, `TreesWatch/WatchLocationManager.swift:55-58`

Both delegates store `locations.last` unconditionally. Core Location's first delivery after `startUpdatingLocation()` is frequently the *last known cached fix* — possibly minutes or hours old, recorded wherever the device last had GPS, often with excellent `horizontalAccuracy` from that earlier moment. So `hasAcceptableAccuracy` passes, the capture button enables instantly, and a tree gets saved with coordinates from a completely different place. This hits hardest in exactly the quick-capture flow the app is built for. Neither delegate rejects invalid fixes (`horizontalAccuracy < 0`) either.

**Fix:** guard in both delegates:
```swift
guard let location = locations.last,
      location.horizontalAccuracy >= 0,
      abs(location.timestamp.timeIntervalSinceNow) < 15 else { return }
```
Apply the same timestamp check in watch `captureLocation()` / `hasAcceptableAccuracy`.

### C-2. iPad: deleting from the detail column re-renders a deleted model → crash
`Trees/Views/TreeDetailView.swift:204-208`, `Trees/Views/CollectionDetailView.swift:170`, `Trees/Views/iPad/iPadContentView.swift:105-109`

On iPad, `TreeDetailView`/`CollectionDetailView` are the `NavigationSplitView` detail column. Their delete buttons call `modelContext.delete(...)` then `dismiss()` — a no-op in a split-view column. `iPadContentView.selectedTree`/`selectedCollection` still reference the deleted model, so `detailColumn` immediately re-renders against it; touching properties of an invalidated `PersistentModel` (guaranteed once CloudKit autosave runs) crashes with "This model instance was invalidated". The list-initiated delete paths nil the selection correctly (`iPadTreeListView.swift:67-71`); the detail-initiated path was missed.

**Fix:** pass an `onDelete` closure into the detail views so `iPadContentView` clears the selection, or guard `detailColumn` with `tree.isDeleted == false && tree.modelContext != nil`.

### C-3. Default JSON import silently discards almost all photos
`Trees/Views/ImportTreesView.swift:70-72, 80-85, 272-317`

In the default `withDelay` mode, the success alert says "Adding N photos in background…" and tapping OK dismisses the view — but `.onDisappear { photoImportTask?.cancel() }` kills the photo task, which sleeps 2s per tree before writing photos. The user taps OK immediately, so the common path imports approximately zero photos, silently.

**Fix:** either let the task run to completion (don't cancel on disappear — it owns its context), or keep the view alive with a progress UI until photos finish.

### C-4. JSON backup round-trip destroys note structure, dates, and photo ownership
`Trees/Services/Exporters/JSONExporter.swift:48-67`, `Trees/Views/ImportTreesView.swift:218-229`

JSON is the designated full-backup format, but export joins all notes into one string (`" | "` separator) and flattens note photos into the tree's photo list. Import then collapses everything into a single Note dated "now" and reattaches all photos directly to the tree. An export → wipe → re-import cycle permanently loses observation history structure, note dates, and the Tree-vs-Note photo ownership the data model is built around. `Photo.id`/`createdAt` are also regenerated.

**Fix:** version the schema; add structured `notes: [{text, createdAt, photos}]` and keep the legacy flat string for backward compatibility. Import prefers the structured field.

### C-5. Fullscreen photo viewer decodes every photo at full resolution, in `body`, eagerly
`Trees/Views/Components/PhotoGalleryView.swift:85-92, 104-109`

`UIImage(data: photo.imageData)` runs inside the `ForEach` of a `.page` TabView, which builds all pages up front — so peak memory is photo-count × full decoded resolution (a 12MP photo decodes to ~48MB), re-done on every swipe because `body` re-evaluates on `currentPhotoID` changes. This is the classic viewer-OOM pattern. Side effects: the ShareLink preview decodes the full image a second time per render, and because each render creates new `UIImage` identities, `ZoomableImageView` resets the zoom whenever the parent re-renders.

**Fix:** load per-page in `.task(id: photo.id)` into `@State`, downsampled to screen size via `ImageDownsampler`; key `ZoomableImageView` resets on `photo.id`, not image identity; downsample the share preview to ~200px.

### C-6. Watch pending-tree queue can be clobbered before it's loaded — permanent field-data loss
`Shared/WatchConnectivityManager.swift:80-104, 118-123`

`loadPendingTrees()` runs only after session activation completes (and after a main-queue hop), but `sendTree` is callable immediately at launch; if the session isn't activated yet it calls `savePendingTrees()`, overwriting the persisted UserDefaults queue with an array containing only the new tree. Trees captured offline in a previous session are silently erased.

**Fix:** load the persisted queue in `init()`/`activate()` before any send path can run.

### C-7. No test targets
`project.yml` defines only the three app targets. The riskiest code is pure, easily testable logic: CSV/JSON/GPX exporters, import parsers, duplicate detection, WatchTreeImporter dedup. Several bugs in this memo (C-3, C-4, M-3, M-4) would have been caught by a round-trip test. Add a `TreesTests` unit-test bundle to project.yml and start with exporter/importer round-trips.

---

## Medium

### Sync & data layer

- **M-1. Export runs synchronously on the main actor.** `ExportView.swift:176-197` uses `Task {}` (main actor) and the exporters are synchronous — reading and base64-encoding every photo blocks the UI end-to-end; the spinner freezes and watchdog termination is plausible for photo-heavy exports. Snapshot model data on the main actor, then encode/write on a background task. Same on the import side: `ImportTreesView.swift:121-133` decodes all base64 photos on the main thread and (in delayed mode) pins every decoded photo in RAM for the whole drip-feed.
- **M-2. Missing `aps-environment` entitlement → CloudKit sync isn't push-driven.** `Trees/Trees.entitlements` has only the iCloud keys; `UIBackgroundModes: [remote-notification]` is set but without the push entitlement CloudKit's silent change notifications don't arrive, so devices only sync on launch/foreground. Xcode normally injects this; the hand-managed entitlements file via xcodegen doesn't. Add `aps-environment: development` (signing rewrites for distribution).
- **M-3. Re-importing a backup duplicates everything.** `ImportTreesView.swift:150-155, 181-194` creates collections unconditionally and remaps already-present tree UUIDs to new IDs, so re-import duplicates every collection, tree, photo, and note. Match collections by exported UUID/name; default to skip-existing for trees.
- **M-4. Collection export drops collection membership.** `CollectionDetailView.swift:155` passes no `collections` to ExportView, so the JSON has `"collections": []` while trees carry dangling `collectionId`s that import silently ignores. Pass `collections: [collection]`.
- **M-5. Watch trees received are silently dropped on decode failure.** `WatchConnectivityManager.swift:149-150` — `transferUserInfo` delivers exactly once; a `try?` decode failure (version skew between watch/phone app updates) loses the tree forever with no log. Also unimplemented `session(_:didFinish:error:)` means permanently failed transfers are invisible, and the UI's "pending" count ignores `session.outstandingUserInfoTransfers`.
- **M-6. Watch import writes through an ad-hoc background ModelContext.** `TreesApp.swift:72-76` creates `ModelContext(modelContainer)` on the main queue instead of using `mainContext`; secondary-context saves don't reliably refresh `@Query` views (imported trees may not appear until relaunch) and races the main context. Use `modelContainer.mainContext`.
- **M-7. No way to delete a photo, and `Tree.removePhoto` would orphan it anyway.** `PhotoGalleryView` is display-only; `Tree.removePhoto` (`Tree.swift:87-90`) has zero callers and only detaches the relationship — the multi-MB Photo row would keep syncing to CloudKit forever. Add a delete affordance in the viewer that does a real `modelContext.delete(photo)`.
- **M-8. Duplicate detection only finds byte-identical coordinates.** `DuplicateTreesView.swift:190-204` buckets on 6-decimal-place strings (~0.11m, not the ~1m the comment claims), so real double-captures with GPS jitter never match — it effectively only finds sync duplicates. Cluster by actual distance (≤5m, same species, close in time) or relabel the feature.
- **M-9. Thumbnail cache key collides.** `ImageDownsampler.swift:10` hashes `data.prefix(16)` — identical for virtually all JPEGs (SOI/APP0 header) — so the key degenerates to byte count; same-length photos display each other's thumbnails. Key by `Photo.id` or hash a wider sample.

### Views & UX

- **M-10. Keystroke-level model mutation in TreeDetailView.** `TreeDetailView.swift:22-57` binds `$tree.species` etc. straight into text fields; autosave can sync half-typed strings to other devices. `CollectionDetailView.swift:17` already documents and solves this pattern with local state — apply it here.
- **M-11. Swipe-delete destroys trees (and their cascaded photos/notes) with no confirmation.** `TreeListView.swift:98-103` — inconsistent with TreeDetailView's confirmed delete; this is the highest-value data in the app. Same for `CollectionListView.swift:74-79`.
- **M-12. Capture/note sheets discard input on swipe-down.** `CaptureTreeView`, `AddNoteView` — add `.interactiveDismissDisabled(hasUnsavedInput)` + discard confirmation.
- **M-13. `centerOnUser()` does nothing on first tap** (both `TreeMapView.swift:123-132` and the copy in `iPadMapView.swift:262-271`): when no fix is cached it requests one but nothing observes the result. Observe `currentLocation` changes with a pending-center flag, or use `.userLocation(fallback:)`.
- **M-14. Search filters in memory on every keystroke.** `TreeListView.swift:15-24` faults `treeNotes` for every tree per keystroke — O(trees × notes) on the main thread. Use `#Predicate`-driven fetches or debounce. The filter logic is also copy-pasted three ways and already drifting (`iPadMapView` uses `localizedCaseInsensitiveContains` while the others use `localizedStandardContains`); `TreeMapView`/`iPadMapView` are ~80% duplicated overall — extract shared helpers.
- **M-15. Library photos stamped with import date, encoded on main thread.** `ImagePicker.swift:85-91` uses `Date()` for `captureDate` (wrong for old library photos) and `jpegData` synchronously. Consider `PHPickerViewController` (multi-select, metadata, no permission prompt) and background encoding.
- **M-16. iPad keyboard shortcuts fire while sheets are open; ⌘N shadows system New Window.** `iPadContentView.swift:72-76, 131-139` — use the `.commands` Scene API or guard on sheet state.
- **M-17. Watch capture dead-ends on denied location permission and never shows GPS errors.** `CaptureView.swift:100-109` hits `default: break` for `.denied`/`.restricted`; `locationError` is never displayed on either platform. Also, the captured fix is frozen with no re-capture affordance even as accuracy improves, and `didFailWithError` treats transient `kCLErrorLocationUnknown` as fatal while leaving `isUpdatingLocation` lying (`LocationManager.swift:59-62`).
- **M-18. Watch complication says "Tap to capture" but only opens the app home.** `TreesWatchWidget.swift:39-60` — no `.widgetURL`/`onOpenURL` anywhere. Add a `trees://capture` deep link or relabel.
- **M-19. CSV formula injection.** `CSVExporter.swift:38-44` doesn't neutralize fields starting with `=`, `+`, `-`, `@` — "spreadsheet compatible" is the format's stated purpose. Apply the standard OWASP prefix mitigation.

---

## Low (condensed)

- **Export/import:** collection names containing `/` or `:` make export silently unrecoverable (`ExportView.swift:50-55` only sanitizes spaces); ISO8601 dates with fractional seconds parse to nil and get rewritten to "now" on import (`ImportTreesView.swift:420-426`); CSV escaping misses `\r`; GPX doesn't strip XML-illegal control chars; streaming JSON export can emit a malformed file if a per-tree encode fails (comma written before encode attempt, `JSONExporter.swift:144-172`); `startAccessingSecurityScopedResource() == false` treated as fatal though it's legitimate for in-container files; decode errors swallowed by `try?` give a useless generic message; export temp file leaks if dismissed mid-export; filename `DateFormatter`s not pinned to `en_US_POSIX`.
- **Views:** whitespace-only note passes the empty check (`TreeDetailView.swift:343` checks pre-trim); collections can be renamed to empty; empty search shows a blank list instead of `ContentUnavailableView.search`; gallery thumbnails invisible to VoiceOver (plain `Image` + `onTapGesture`, unlabeled remove button); `ZoomableImageView` mis-frames on rotation while zoomed; local `struct PhotosPicker` shadows `PhotosUI.PhotosPicker`; `SpeciesTextField` re-fetches all trees on every `onAppear`; `TreeListView`/`ContentView` previews crash (missing `PhotoViewerState` environment); persistence discipline is inconsistent (some paths explicit-save with rollback, others rely on autosave — `DuplicateTreesView.deleteSelected` also recomputes from a possibly-stale `@Query` immediately after deleting).
- **Watch/iPad:** in-progress watch capture state lost on suspension (consider a UserDefaults draft); `lastCapturedTree` not persisted; unused `if let location =` binding warning (`CaptureView.swift:29`); iPad map search filters the panel but not the pins (`iPadMapView.swift:33-34`); dead `case .map: EmptyView()` in `iPadContentView`; photo-viewer toolbar hiding applied in `iPadTreeListView` but not collection/map; iPad ⌘E opens Export with zero trees; pending-queue cap of 100 drops oldest silently.
- **Models:** `updatedAt` not bumped on direct `@Bindable` field edits; model class `Collection` shadows `Swift.Collection` (rename is cheap now, costly after more CloudKit data exists); `activationDidCompleteWith` ignores its `error` parameter.
- **Config:** CLAUDE.md documents a `TreesWatch` scheme that doesn't exist; widget target missing `GENERATE_INFOPLIST_FILE: false`; `xcodeVersion: "15.0"` incompatible with watchOS 11 targets; stray macOS deployment target with no macOS target; Catalyst enabled but no App Sandbox entitlement.

---

## Feature improvements worth considering

**Field-capture quality (the app's core):**
- GPS re-capture / best-fix tracking: both capture flows freeze the first acceptable fix even as accuracy improves; offer re-capture or auto-keep the best fix until save. Consider averaging the last N fixes weighted by accuracy.
- Watch: pre-fill last-used species; allow saving with species "Unknown" (currently required on watch but not iPhone); haptic on save; show distance from last captured tree to avoid double-captures.
- Sync the user's actual species history to the watch via `updateApplicationContext` instead of the static `commonSpecies` list.

**Data management:**
- Stored thumbnail blob on `Photo` generated at capture — structurally fixes list-scroll jank (M-9/M-2-style faulting) and makes CloudKit-synced lists render before full assets arrive.
- Versioned, structured backup format (ties to C-4); longer term, a ZIP export with photos as real files instead of base64 (~25% smaller, streamable, recoverable without the app).
- Duplicate "merge" action (move photos/notes to the keeper) instead of delete-only.
- Import/export progress UI with cancellation once the work moves off the main actor.
- Edit existing notes (currently delete-only); move trees between collections (the picker only offers unassigned trees); CSV `collection` column; GPX `<hdop>` + extensions for variety/rootstock.

**Platform polish:**
- Map pin clustering for dense orchards (both map views).
- iPad multi-select for bulk delete / bulk add-to-collection.
- Surface CloudKit sync health by observing `NSPersistentCloudKitContainer.eventChangedNotification` (currently failures are a `print`).
- iOS toast/badge when a watch tree arrives (imports are currently silent).

---

## Suggested order of attack

1. **C-1** (stale GPS guard) — a few lines, protects the core data the app exists to collect.
2. **C-2** (iPad delete crash) and **C-6** (watch queue clobber) — crash + data loss, both small fixes.
3. **C-3 + M-3/M-4** (import photo loss, idempotency, collection membership) — the import path is the most bug-dense area.
4. **C-4** (structured backup schema) — design once, fixes round-trip fidelity permanently.
5. **C-5 + M-9** (photo viewer memory, cache key) — stability under real photo loads.
6. **C-7** (tests) — lock in the exporter/importer fixes with round-trip tests as they land.
