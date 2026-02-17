# Architecture

This document describes the software architecture of the Tree Tracker iOS and watchOS apps.

## Overview

Tree Tracker is a SwiftUI app for capturing and managing GPS locations of trees. It follows Apple's modern app development patterns using SwiftUI for the UI layer and SwiftData for persistence. The app includes a watchOS companion app for quick tree capture and a WidgetKit complication for watch face integration.

```
┌─────────────────────────────────────────────────────────────┐
│                         TreesApp                            │
│                    (App Entry Point)                        │
├─────────────────────────────────────────────────────────────┤
│                        ContentView                          │
│            (Tab Navigation / Split View)                    │
├───────────────┬───────────────────────┬─────────────────────┤
│  TreeListView │  CollectionListView   │    TreeMapView      │
│   (Tab 1)     │       (Tab 2)         │      (Tab 3)        │
└───────────────┴───────────────────────┴─────────────────────┘
         │                  │                     │
         ▼                  ▼                     ▼
┌─────────────────────────────────────────────────────────────┐
│                      SwiftData Layer                        │
│         ModelContainer (Tree, Collection, Photo, Note)      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     CloudKit Sync                           │
│              iCloud.com.treetracker.Trees                   │
└─────────────────────────────────────────────────────────────┘
```

## Technology Stack

| Layer | Technology |
|-------|------------|
| UI Framework | SwiftUI (iOS 17+, watchOS 11+) |
| Persistence | SwiftData with CloudKit |
| Cloud Sync | CloudKit (private database) |
| Location | Core Location |
| Maps | MapKit |
| Photos | PhotosUI, UIImagePickerController |
| Watch Sync | WatchConnectivity |
| Complications | WidgetKit |
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
    var collection: Collection?       // Optional grouping
    var createdAt: Date
    var updatedAt: Date

    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \Photo.tree)
    var photos: [Photo]?              // Photos directly attached to tree

    @Relationship(deleteRule: .cascade, inverse: \Note.tree)
    var notes: [Note]?                // Dated observations/notes
}
```

Helper computed properties: `treePhotos`, `treeNotes`, `allPhotos` (includes note photos).

### Photo

Individual photo entity for CloudKit-compatible sync.

```swift
@Model
class Photo {
    var id: UUID
    @Attribute(.externalStorage) var imageData: Data  // Single JPEG asset
    var captureDate: Date?
    var createdAt: Date

    // A photo belongs to either a Tree directly OR a Note (not both)
    var tree: Tree?
    var note: Note?
}
```

Photos use `.externalStorage` to store as CKAsset in CloudKit, enabling reliable sync of large binary data.

### Note

Dated observation or note about a tree, with optional attached photos.

```swift
@Model
class Note {
    var id: UUID
    var text: String
    var createdAt: Date
    var updatedAt: Date
    var tree: Tree?                   // Which tree this note belongs to

    @Relationship(deleteRule: .cascade, inverse: \Photo.note)
    var photos: [Photo]?              // Photos attached to this note
}
```

### Collection

Groups trees into named collections (e.g., "Victoria's Orchard").

```swift
@Model
class Collection {
    var id: UUID
    var name: String
    @Relationship(deleteRule: .nullify, inverse: \Tree.collection)
    var trees: [Tree]?
    var createdAt: Date
    var updatedAt: Date
}
```

The relationship uses `.nullify` delete rule: when a collection is deleted, its trees remain but lose their collection assignment.

## View Architecture

### Navigation Structure

**iPhone (compact width):**
```
ContentView (TabView)
├── Tab 1: TreeListView
│   ├── TreeRowView (list item)
│   ├── → TreeDetailView (navigation destination)
│   │   ├── NoteRowView (note items)
│   │   └── → AddNoteView (sheet)
│   ├── → CaptureTreeView (sheet)
│   ├── → ExportView (sheet)
│   ├── → ImportTreesView (sheet)
│   └── → DuplicateTreesView (sheet)
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

**iPad (regular width):**
```
ContentView (NavigationSplitView)
├── Sidebar: iPadSidebarView
│   ├── Trees
│   ├── Collections
│   └── Map
├── Content: iPadTreeListView / iPadCollectionListView
└── Detail: TreeDetailView / CollectionDetailView
```

### Key Views

| View | Purpose |
|------|---------|
| `TreeListView` | Main list of all trees with search and swipe-to-delete |
| `TreeRowView` | Compact row showing photo thumbnail, species, variety, accuracy badge |
| `TreeDetailView` | Full tree details with embedded map, edit mode, photo gallery, notes list |
| `TreeMapView` | MapKit view with all trees as pins, toggle species/variety labels |
| `CaptureTreeView` | New tree entry with live GPS accuracy, collection picker, photo capture, initial note |
| `CollectionListView` | List of collections with tree counts |
| `CollectionDetailView` | Collection contents, add/remove trees, export |
| `ExportView` | Format selection (CSV/JSON/GPX) and share sheet |
| `ImportTreesView` | Import trees from JSON with photo import options |
| `ImportCollectionView` | Parse JSON export into new collection |
| `DuplicateTreesView` | Find and delete duplicate trees by location + species |
| `AddNoteView` | Add new note with optional photos to a tree |

### Reusable Components

| Component | Purpose |
|-----------|---------|
| `AccuracyBadge` | Color-coded accuracy display (green/yellow/red) |
| `LiveAccuracyView` | Real-time GPS accuracy during capture |
| `PhotoGalleryView` | Grid display of Photo entities with fullscreen viewer and dates |
| `EditablePhotoGalleryView` | Photo grid with delete capability (works with raw Data) |
| `PhotosPicker` | Camera/library photo selection |
| `ImagePicker` | UIImagePickerController wrapper |
| `SpeciesTextField` | Text field with autocomplete from preset + used species |
| `NoteRowView` | Displays a Note with date, text, and thumbnail photos |
| `ImageDownsampler` | Memory-efficient thumbnail creation with NSCache |

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

All exporters combine multiple notes into a single text field for compatibility:
```swift
let allNotesText = tree.treeNotes.map { $0.text }.joined(separator: " | ")
```

Files are written to the app's temporary directory with timestamped filenames.

### WatchConnectivityManager

Shared service (in `Shared/`) handling iPhone ↔ Watch communication via `WCSession`.

```swift
@Observable
class WatchConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()
    var pendingTrees: [WatchTree]  // Queue for offline sync (capped at 100)

    func sendTree(_ tree: WatchTree)  // Watch → iPhone (main thread only)
    func activate()                    // Called on app launch
}
```

Uses `transferUserInfo()` for reliable background delivery of captured trees.

### WatchTreeImporter

iOS-only service that converts incoming `WatchTree` objects to SwiftData `Tree` entities.

```swift
struct WatchTreeImporter {
    func importTree(_ watchTree: WatchTree) -> Tree?
}
```

- Prevents duplicates by checking for existing trees with matching UUID
- Creates a Note entity from watch notes if provided

## Watch App Architecture

### Overview

The watchOS companion app provides quick tree capture from the wrist. It's a lightweight capture tool—photos and collection assignment happen on iPhone.

```
┌─────────────────────────────────────────────────────────────┐
│                     TreesWatchApp                           │
│                    (Watch Entry Point)                      │
├─────────────────────────────────────────────────────────────┤
│                        ContentView                          │
│                  (Capture Button + Status)                  │
├─────────────────────────────────────────────────────────────┤
│                       CaptureView                           │
│          (GPS Accuracy + Species + Notes + Save)            │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                 WatchConnectivityManager                    │
│           (Sync to iPhone via WCSession)                    │
└─────────────────────────────────────────────────────────────┘
```

### WatchTree

Lightweight Codable struct for Watch → iPhone transfer (not a SwiftData model):

```swift
struct WatchTree: Codable, Identifiable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let altitude: Double?
    let species: String
    let notes: String
    let capturedAt: Date
}
```

### Watch Views

| View | Purpose |
|------|---------|
| `ContentView` | Large "Capture Tree" button, last capture info, pending sync count |
| `CaptureView` | GPS capture flow with accuracy ring, species picker, notes |
| `SpeciesPickerView` | List of 50+ species with search and voice dictation |
| `AccuracyRingView` | Circular progress showing GPS accuracy status |

### WatchLocationManager

Watch-specific `@Observable` wrapper for `CLLocationManager`:

```swift
@Observable
class WatchLocationManager: NSObject, CLLocationManagerDelegate {
    var currentLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus
    var isUpdatingLocation: Bool
    var hasAcceptableAccuracy: Bool  // < 25 meters for Watch
}
```

Uses higher accuracy threshold (25m vs 20m on iPhone) to account for Watch GPS limitations.

## Watch Complication

WidgetKit-based complication for quick app launch from watch face.

### Supported Families

| Family | Appearance |
|--------|------------|
| `accessoryCircular` | Tree icon on circular background |
| `accessoryCorner` | Tree icon with "Capture" label |
| `accessoryRectangular` | Tree icon with "Tree Tracker" title |
| `accessoryInline` | "Capture Tree" text with icon |

### Implementation

Uses `StaticConfiguration` (no dynamic data needed—purely a launch button):

```swift
@main
struct TreesWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TreesWatchWidget", provider: Provider()) { entry in
            TreesWatchWidgetEntryView(entry: entry)
        }
        .supportedFamilies([.accessoryCircular, .accessoryCorner, ...])
    }
}
```

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
         User enters species, notes, selects collection, adds photos
                      │
                      ▼
         User taps "Save"
                      │
                      ▼
         Tree inserted into ModelContext
                      │
                      ▼
         Photo entities created for each photo
                      │
                      ▼
         Note entity created if initial note provided
                      │
                      ▼
         lastUsedCollectionID saved to @AppStorage
                      │
                      ▼
         CloudKit syncs to other devices
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
Trees/                              # iOS App
├── TreesApp.swift                 # App entry, ModelContainer setup, CloudKit config
├── Trees.entitlements             # iCloud/CloudKit entitlements
├── Models/
│   ├── Tree.swift                 # Tree entity + computed properties
│   ├── Photo.swift                # Photo entity (single asset)
│   ├── Note.swift                 # Note entity with photos
│   ├── Collection.swift           # Collection entity
│   └── TreesSchema.swift          # Versioned schema + migration plan
├── Services/
│   ├── LocationManager.swift      # Core Location wrapper
│   ├── WatchTreeImporter.swift    # Convert WatchTree → Tree + Note
│   └── Exporters/
│       ├── CSVExporter.swift
│       ├── JSONExporter.swift
│       └── GPXExporter.swift
├── Utilities/
│   └── ImageDownsampler.swift     # Thumbnail creation with NSCache
├── Views/
│   ├── ContentView.swift          # TabView/SplitView root
│   ├── TreeListView.swift
│   ├── TreeRowView.swift
│   ├── TreeMapView.swift
│   ├── TreeDetailView.swift       # Includes NoteRowView, AddNoteView
│   ├── CaptureTreeView.swift
│   ├── ExportView.swift
│   ├── CollectionListView.swift
│   ├── CollectionDetailView.swift
│   ├── ImportCollectionView.swift
│   ├── ImportTreesView.swift
│   ├── DuplicateTreesView.swift   # Find and delete duplicate trees
│   ├── iPad/                      # iPad-specific views
│   │   ├── iPadContentView.swift
│   │   ├── iPadSidebarView.swift
│   │   ├── iPadTreeListView.swift
│   │   ├── iPadCollectionListView.swift
│   │   └── iPadMapView.swift
│   └── Components/
│       ├── AccuracyBadge.swift
│       ├── ImagePicker.swift      # Includes PhotosPicker
│       ├── PhotoGalleryView.swift # Includes EditablePhotoGalleryView, PhotoDetailView
│       └── SpeciesTextField.swift
└── Assets.xcassets/

Shared/                             # Shared between iOS and watchOS
├── WatchConnectivityManager.swift  # WCSession wrapper
├── WatchTree.swift                 # Codable transfer struct
└── CommonSpecies.swift             # Preset species list (50+)

TreesWatch/                         # watchOS App
├── TreesWatchApp.swift             # Watch app entry
├── ContentView.swift               # Main view with capture button
├── CaptureView.swift               # GPS capture flow
├── WatchLocationManager.swift      # Watch-specific location manager
└── Assets.xcassets/

TreesWatchWidget/                   # Watch Complication
├── TreesWatchWidget.swift          # Widget configuration + views
└── Assets.xcassets/
```

## Design Decisions

### Why SwiftData over Core Data?

- Simpler API with `@Model` macro
- Native SwiftUI integration with `@Query`
- Automatic schema migrations for simple changes
- Built-in CloudKit integration
- iOS 17+ only, but acceptable for new app

### Why @Observable over ObservableObject?

- Cleaner syntax (no `@Published` needed)
- Better performance (fine-grained observation)
- iOS 17+ feature, aligns with SwiftData requirement

### Photo Storage Strategy

Photos stored as individual `Photo` entities with single `Data` asset:
- Each photo is its own CloudKit record with CKAsset
- Enables reliable sync of photos between devices
- Previous approach (array of Data) didn't sync reliably
- Trade-off: More records, but better CloudKit compatibility

### Notes as Entities

Notes stored as individual `Note` entities instead of single String field:
- Enables multiple dated observations per tree
- Each note can have its own attached photos
- Notes sync reliably via CloudKit
- Export combines notes for backward compatibility

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

## iCloud Sync

### Configuration

CloudKit sync enabled via SwiftData's `cloudKitDatabase` configuration. If CloudKit initialization fails, the app falls back to local-only storage automatically:
```swift
// Primary: CloudKit-backed
ModelConfiguration(
    schema: schema,
    cloudKitDatabase: .private("iCloud.com.treetracker.Trees")
)

// Fallback: local-only (if CloudKit fails)
ModelConfiguration(schema: schema)
```

### CloudKit Record Types

SwiftData automatically creates CloudKit record types:
- `CD_Tree` - Tree records
- `CD_Photo` - Photo records with CKAsset for imageData
- `CD_Note` - Note records
- `CD_Collection` - Collection records

### Sync Behavior

- Automatic sync when device is online
- Photos sync as CKAsset (reliable for large data)
- Conflicts resolved automatically by SwiftData
- Requires user signed into iCloud

## Offline Capability

The app is fully offline-capable:
- SwiftData persists all data locally
- Photos stored as binary data, not URLs
- No network requests required for core functionality
- Export files written to temporary directory before sharing
- CloudKit syncs when connectivity restored
