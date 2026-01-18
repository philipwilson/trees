# Architecture

This document describes the software architecture of the Tree Tracker iOS app.

## Overview

Tree Tracker is a SwiftUI app for capturing and managing GPS locations of trees. It follows Apple's modern app development patterns using SwiftUI for the UI layer and SwiftData for persistence.

```
┌─────────────────────────────────────────────────────────────┐
│                         TreesApp                            │
│                    (App Entry Point)                        │
├─────────────────────────────────────────────────────────────┤
│                        ContentView                          │
│                    (Tab Navigation)                         │
├───────────────┬───────────────────────┬─────────────────────┤
│  TreeListView │  CollectionListView   │    TreeMapView      │
│   (Tab 1)     │       (Tab 2)         │      (Tab 3)        │
└───────────────┴───────────────────────┴─────────────────────┘
         │                  │                     │
         ▼                  ▼                     ▼
┌─────────────────────────────────────────────────────────────┐
│                      SwiftData Layer                        │
│              ModelContainer (Tree, Collection)              │
└─────────────────────────────────────────────────────────────┘
```

## Technology Stack

| Layer | Technology |
|-------|------------|
| UI Framework | SwiftUI (iOS 17+) |
| Persistence | SwiftData |
| Location | Core Location |
| Maps | MapKit |
| Photos | PhotosUI, UIImagePickerController |
| Project Generation | xcodegen |

## Data Model

### Tree

The primary entity representing a captured tree location.

```swift
@Model
class Tree {
    var id: UUID
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double    // GPS accuracy in meters
    var altitude: Double?
    var species: String
    var variety: String?              // e.g., "Honeycrisp" for Apple
    var rootstock: String?            // e.g., "M111" for grafted trees
    var notes: String
    @Attribute(.externalStorage) var photos: [Data]  // JPEG data
    var collection: Collection?       // Optional grouping
    var createdAt: Date
    var updatedAt: Date
}
```

Photos use `.externalStorage` to store large binary data outside the main database file.

### Collection

Groups trees into named collections (e.g., "Victoria's Orchard").

```swift
@Model
class Collection {
    var id: UUID
    var name: String
    @Relationship(deleteRule: .nullify, inverse: \Tree.collection)
    var trees: [Tree]
    var createdAt: Date
    var updatedAt: Date
}
```

The relationship uses `.nullify` delete rule: when a collection is deleted, its trees remain but lose their collection assignment.

## View Architecture

### Navigation Structure

```
ContentView (TabView)
├── Tab 1: TreeListView
│   ├── TreeRowView (list item)
│   ├── → TreeDetailView (navigation destination)
│   ├── → CaptureTreeView (sheet)
│   └── → ExportView (sheet)
│
├── Tab 2: CollectionListView
│   ├── → CollectionDetailView (navigation destination)
│   │   ├── TreeRowView (list item)
│   │   ├── → CaptureTreeView (sheet, preselected collection)
│   │   └── → ExportView (sheet, collection-scoped)
│   └── → ImportCollectionView (sheet)
│
└── Tab 3: TreeMapView
    ├── TreeMapPin (annotation view)
    ├── → TreeDetailView (sheet on selection)
    └── → CaptureTreeView (sheet)
```

### Key Views

| View | Purpose |
|------|---------|
| `TreeListView` | Main list of all trees with search and swipe-to-delete |
| `TreeRowView` | Compact row showing photo thumbnail, species, variety, accuracy badge |
| `TreeDetailView` | Full tree details with embedded map, edit mode, photo gallery |
| `TreeMapView` | MapKit view with all trees as pins, toggle species/variety labels |
| `CaptureTreeView` | New tree entry with live GPS accuracy, collection picker, photo capture |
| `CollectionListView` | List of collections with tree counts |
| `CollectionDetailView` | Collection contents, add/remove trees, export |
| `ExportView` | Format selection (CSV/JSON/GPX) and share sheet |
| `ImportCollectionView` | Parse JSON export into new collection |

### Reusable Components

| Component | Purpose |
|-----------|---------|
| `AccuracyBadge` | Color-coded accuracy display (green/yellow/red) |
| `LiveAccuracyView` | Real-time GPS accuracy during capture |
| `PhotoGalleryView` | Grid display of photos with fullscreen viewer |
| `EditablePhotoGalleryView` | PhotoGalleryView with delete capability |
| `PhotosPicker` | Camera/library photo selection |
| `ImagePicker` | UIImagePickerController wrapper |

## Services

### LocationManager

Wraps `CLLocationManager` with an `@Observable` interface for SwiftUI.

```swift
@Observable
class LocationManager: NSObject, CLLocationManagerDelegate {
    var currentLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus
    var isUpdatingLocation: Bool

    var hasGoodAccuracy: Bool      // < 10 meters
    var hasAcceptableAccuracy: Bool // < 20 meters
}
```

Configuration for maximum GPS accuracy:
- `desiredAccuracy = kCLLocationAccuracyBest`
- `distanceFilter = kCLDistanceFilterNone`
- `activityType = .fitness`

### Exporters

Three exporters in `Services/Exporters/` convert tree data to different formats:

| Exporter | Format | Use Case |
|----------|--------|----------|
| `CSVExporter` | Comma-separated values | Spreadsheet import (Excel, Numbers) |
| `JSONExporter` | JSON array | Data interchange, backup (optional base64 photos) |
| `GPXExporter` | GPX 1.1 XML | GPS apps (Google Earth, Gaia GPS, etc.) |

All exporters follow the same pattern:
```swift
struct CSVExporter {
    static func export(trees: [Tree]) -> String
    static func exportToFile(trees: [Tree], filePrefix: String) -> URL?
}
```

Files are written to the app's cache directory with timestamped filenames.

## Data Flow

### Capturing a Tree

```
User taps "+" → CaptureTreeView presented
                      │
                      ▼
         LocationManager.startUpdatingLocation()
                      │
                      ▼
         LiveAccuracyView shows real-time accuracy
                      │
                      ▼ (accuracy < 20m)
         "Capture Location" button enabled
                      │
                      ▼
         User taps → location frozen
                      │
                      ▼
         User enters species, notes, selects collection
                      │
                      ▼
         User taps "Save"
                      │
                      ▼
         Tree inserted into ModelContext
                      │
                      ▼
         lastUsedCollectionID saved to @AppStorage
                      │
                      ▼
         View dismissed, list auto-updates via @Query
```

### SwiftData Queries

Views use `@Query` for reactive data fetching:

```swift
// TreeListView - all trees, newest first
@Query(sort: \Tree.createdAt, order: .reverse) private var trees: [Tree]

// CollectionListView - alphabetical
@Query(sort: \Collection.name) private var collections: [Collection]

// CaptureTreeView - for collection picker
@Query(sort: \Collection.name) private var collections: [Collection]
```

### User Preferences

Persisted via `@AppStorage` (UserDefaults):

| Key | Type | Purpose |
|-----|------|---------|
| `lastUsedCollectionID` | String? | Default collection for new trees |
| `mapShowVariety` | Bool | Show variety instead of species on map pins |

## File Structure

```
Trees/
├── TreesApp.swift                 # App entry, ModelContainer setup
├── Models/
│   ├── Tree.swift                 # Tree entity + computed properties
│   └── Collection.swift           # Collection entity
├── Services/
│   ├── LocationManager.swift      # Core Location wrapper
│   └── Exporters/
│       ├── CSVExporter.swift
│       ├── JSONExporter.swift
│       └── GPXExporter.swift
├── Views/
│   ├── ContentView.swift          # TabView root
│   ├── TreeListView.swift
│   ├── TreeRowView.swift
│   ├── TreeMapView.swift
│   ├── TreeDetailView.swift
│   ├── CaptureTreeView.swift
│   ├── ExportView.swift
│   ├── CollectionListView.swift
│   ├── CollectionDetailView.swift
│   ├── ImportCollectionView.swift
│   └── Components/
│       ├── AccuracyBadge.swift
│       ├── ImagePicker.swift
│       └── PhotoGalleryView.swift
└── Assets.xcassets/
    ├── AppIcon.appiconset/
    └── AccentColor.colorset/
```

## Design Decisions

### Why SwiftData over Core Data?

- Simpler API with `@Model` macro
- Native SwiftUI integration with `@Query`
- Automatic schema migrations for simple changes
- iOS 17+ only, but acceptable for new app

### Why @Observable over ObservableObject?

- Cleaner syntax (no `@Published` needed)
- Better performance (fine-grained observation)
- iOS 17+ feature, aligns with SwiftData requirement

### Photo Storage Strategy

Photos stored as `[Data]` with `.externalStorage`:
- Keeps main database file small
- SwiftData handles file management
- Trade-off: No lazy loading, all photo data loads with tree

### GPS Accuracy Thresholds

| Accuracy | Classification | Color |
|----------|----------------|-------|
| < 5m | Excellent | Green |
| < 10m | Good | Green |
| < 15m | Acceptable | Yellow |
| < 20m | Marginal | Orange |
| ≥ 20m | Poor | Red |

Capture requires < 20m accuracy. Users are encouraged to wait for < 10m.

### Export File Naming

Pattern: `{prefix}_{timestamp}.{ext}`

Examples:
- `trees_2024-03-15_143022.csv` (all trees)
- `victorias_orchard_2024-03-15_143022.gpx` (collection export)

## Offline Capability

The app is fully offline-capable:
- SwiftData persists all data locally
- Photos stored as binary data, not URLs
- No network requests required
- Export files saved locally before sharing

## Future Considerations

Potential enhancements the architecture could support:
- iCloud sync via SwiftData CloudKit integration
- Background location updates for automatic capture
- Custom tree icons based on species
- Photo thumbnails for faster list scrolling
- Batch import from GPX files
