# Shared Trees Database Review

Date: 2026-02-12

## Findings

1. **High**: Several create/delete flows still rely on implicit SwiftData autosave rather than explicit `save()`. In crash/termination windows, recent writes can be lost. (`Trees/Views/CaptureTreeView.swift:169`, `Trees/Views/CaptureTreeView.swift:199`, `Trees/Views/CollectionListView.swift:64`, `Trees/Views/CollectionListView.swift:71`, `Trees/Views/TreeListView.swift:97`, `Trees/Views/iPad/iPadContentView.swift:117`, `Trees/Views/iPad/iPadCollectionListView.swift:39`, `Trees/Views/iPad/iPadTreeListView.swift:68`)

2. **Medium**: Logical IDs are still application-managed (no DB-level uniqueness on `Tree.id` / `Collection.id`). Import paths now mitigate collisions, but integrity depends on all code paths continuing to do so correctly. (`Trees/Models/Tree.swift:6`, `Trees/Models/Collection.swift:6`, `Trees/Views/ImportTreesView.swift:134`, `Trees/Views/ImportCollectionView.swift:132`, `Trees/Services/WatchTreeImporter.swift:14`)

3. **Medium**: Migration scaffolding is present but only a single schema version exists and there are no migration tests yet, so future model evolution remains risky if schema changes are introduced quickly. (`Trees/Models/TreesSchema.swift:3`, `Trees/Models/TreesSchema.swift:13`)

## Export Audit (2026-02-12)

- `db-export.json`
  - collections: `3`
  - trees: `129`
  - duplicate tree IDs: `0`
  - duplicate collection IDs: `0`
  - invalid coordinate/accuracy/date format anomalies: none found
  - data quality: `species` whitespace issues `1`, `variety` whitespace issues `8`
  - relationship state: trees currently have no `collectionId` links (consistent with your note that collections need rebuilding)

- `db-export-photos.json` (~113 MB)
  - tree/photo integrity checks passed
  - `photoCount` sum = `16`
  - photos array item sum = `16`
  - photoDates item sum = `16`
  - base64 decode failures = `0`
  - decoded bytes total = `87,385,832`

## Best-Practice Status

The project is **partially aligned** with shared-database best practices:

- In good shape:
  - Versioned schema + migration plan scaffolding is now in place.
  - Watch pending-queue dedupe/persistence and import error handling were hardened.
  - Import ID-collision handling and duplicate-delete identity safety were hardened.

- Still needs work:
  - Make critical write paths explicit (`try modelContext.save()` with user-visible failure handling).
  - Decide whether to enforce unique logical IDs at the model level in a planned migration.
  - Add automated tests for import/export/migration integrity.

## Repair Tooling Added

- Script: `Scripts/repair_export.swift`
- Template starter: `Scripts/tree-collection-map.template.csv`
- Generated scaffold from your current export: `Scripts/tree-collection-map.from-export.csv`

### Repair workflow

1. Fill `Scripts/tree-collection-map.from-export.csv` column `collection_name` (leave blank to clear).
2. Run:

```bash
swift Scripts/repair_export.swift \
  --input db-export-photos.json \
  --mapping Scripts/tree-collection-map.from-export.csv \
  --output db-export-photos-repaired.json
```

3. Import `db-export-photos-repaired.json`.
