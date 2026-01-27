# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Regenerate Xcode project from project.yml (after modifying project.yml)
xcodegen generate

# Build iOS app for simulator
xcodebuild -project Trees.xcodeproj -scheme Trees -destination 'platform=iOS Simulator,name=iPhone 17' build

# Build Watch app for simulator
xcodebuild -project Trees.xcodeproj -scheme TreesWatch -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 3 (49mm)' build

# Build for physical device (requires signing configured in Xcode)
xcodebuild -project Trees.xcodeproj -scheme Trees -destination 'generic/platform=iOS' build

# Run on simulator
xcrun simctl install booted ~/Library/Developer/Xcode/DerivedData/Trees-*/Build/Products/Debug-iphonesimulator/Trees.app
xcrun simctl launch booted com.treetracker.Trees

# Open in Xcode
open Trees.xcodeproj
```

## Architecture

iOS app using SwiftUI + SwiftData (iOS 17+) with watchOS companion app (watchOS 11+). Project generated via xcodegen from `project.yml`.

### Data Flow
- **Tree** (@Model): SwiftData entity storing GPS coordinates, accuracy, species, variety, rootstock, and optional Collection relationship
- **Photo** (@Model): Individual photo with single Data asset (external storage), belongs to Tree or Note
- **Note** (@Model): Dated observation/note text with optional attached photos, belongs to Tree
- **Collection** (@Model): Named group of trees with one-to-many relationship (deleteRule: nullify)
- **LocationManager** (@Observable): Wraps CLLocationManager with `kCLLocationAccuracyBest` for precise GPS capture
- **SwiftData ModelContainer**: Configured in TreesApp.swift for Tree, Collection, Photo, and Note models

### Watch App (TreesWatch/)
Companion watchOS app for quick tree capture from the wrist.

**Data Flow:**
- **WatchTree** (Codable struct in `Shared/`): Lightweight transfer object for Watch→iPhone sync
- **WatchConnectivityManager** (@Observable in `Shared/`): WCSession wrapper handling bidirectional sync
- **WatchTreeImporter** (iOS only): Converts WatchTree to SwiftData Tree entity, creates Note from watch notes

**Sync Behavior:**
- Trees sent via `WCSession.transferUserInfo()` for reliable background delivery
- Pending trees queued locally if iPhone unreachable, retried on reconnection
- Duplicates prevented by matching on tree UUID

### Watch Complication (TreesWatchWidget/)
WidgetKit-based complication for quick app launch from watch face.

**Supported Families:**
- `accessoryCircular` - Tree icon on circular background
- `accessoryCorner` - Tree icon with "Capture" label
- `accessoryRectangular` - Tree icon with "Tree Tracker" text
- `accessoryInline` - "Capture Tree" text with icon

**Files:**
- `TreesWatchWidget.swift` - Widget configuration and entry views

### View Hierarchy
- **ContentView**: TabView with Trees, Collections, and Map tabs (iPhone) or NavigationSplitView (iPad)
- **TreeListView**: @Query fetches trees, search filters by species/variety/notes, triggers CaptureTreeView and ExportView
- **TreeMapView**: MapKit with tree annotations, toolbar toggle to show variety instead of species
- **CaptureTreeView**: Live GPS accuracy, collection picker (defaults to last used via @AppStorage), photo picker, initial note
- **TreeDetailView**: @Bindable tree for inline editing, collection assignment, embedded map, photo gallery, notes list with Add Note
- **CollectionListView**: List all collections, create new, import from JSON
- **CollectionDetailView**: View/edit collection, add/remove trees, export collection

### Export/Import System
Three exporters in `Services/Exporters/` produce file URLs for sharing (accept optional `filePrefix` for collection exports):
- **CSVExporter**: Spreadsheet format with all tree fields (notes combined as text)
- **JSONExporter**: Full data with optional base64-encoded photos
- **GPXExporter**: Standard GPS waypoint format for mapping apps

Import via **ImportCollectionView** and **ImportTreesView**: parses JSON exports into collections or standalone trees.

### UI Components
- **AccuracyBadge**: Color-coded accuracy display (green < 5m, yellow < 15m, red > 15m)
- **ImagePicker**: UIImagePickerController wrapper for camera/library
- **PhotoGalleryView**: Grid display of Photo entities with fullscreen viewer, shows photo dates when available
- **EditablePhotoGalleryView**: For adding photos during capture/editing (works with raw Data before Photo entities created)
- **SpeciesTextField**: Text field with autocomplete suggestions from preset species + previously-used species
- **NoteRowView**: Displays a Note with date, text, and thumbnail photos
- **AddNoteView**: Sheet for adding new notes with optional photos

### iPad Support (Trees/Views/iPad/)
Adaptive layout using `horizontalSizeClass` environment value:
- **iPhone (compact)**: TabView with Trees, Collections, Map tabs
- **iPad (regular)**: NavigationSplitView with sidebar, list, and detail columns

**iPad-specific views:**
- `iPadContentView` - Main split view layout with keyboard shortcuts (⌘N, ⌘E, ⌘1/2/3)
- `iPadSidebarView` - Sidebar navigation with badge counts
- `iPadTreeListView` / `iPadCollectionListView` - Selection-bound lists with context menus
- `iPadMapView` - Full-width map with collapsible floating tree list panel

## iCloud Sync

iCloud sync via CloudKit is enabled. Trees, Collections, Photos, and Notes sync automatically between devices signed into the same iCloud account.

### Configuration

To disable iCloud sync (e.g., for testing), set `enableCloudKit = false` in `Trees/TreesApp.swift` line 11.

### How iCloud Sync Works
- Uses SwiftData with CloudKit private database
- Container: `iCloud.com.treetracker.Trees`
- Syncs Trees, Collections, Photos, and Notes automatically between devices
- Photos stored as individual Photo entities with single Data asset (CKAsset) for reliable sync
- Requires user to be signed into iCloud on all devices
