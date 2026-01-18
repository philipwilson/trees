# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Regenerate Xcode project from project.yml (after modifying project.yml)
xcodegen generate

# Build for simulator
xcodebuild -project Trees.xcodeproj -scheme Trees -destination 'platform=iOS Simulator,name=iPhone 17' build

# Build for physical device (requires signing configured in Xcode)
xcodebuild -project Trees.xcodeproj -scheme Trees -destination 'generic/platform=iOS' build

# Run on simulator
xcrun simctl install booted ~/Library/Developer/Xcode/DerivedData/Trees-*/Build/Products/Debug-iphonesimulator/Trees.app
xcrun simctl launch booted com.treetracker.Trees

# Open in Xcode
open Trees.xcodeproj
```

## Architecture

iOS app using SwiftUI + SwiftData (iOS 17+). Project generated via xcodegen from `project.yml`.

### Data Flow
- **Tree** (@Model): SwiftData entity storing GPS coordinates, accuracy, species, variety, rootstock, notes, photos (JPEG Data with external storage), and optional Collection relationship
- **Collection** (@Model): Named group of trees with one-to-many relationship (deleteRule: nullify)
- **LocationManager** (@Observable): Wraps CLLocationManager with `kCLLocationAccuracyBest` for precise GPS capture
- **SwiftData ModelContainer**: Configured in TreesApp.swift for both Tree and Collection models

### View Hierarchy
- **ContentView**: TabView with Trees, Collections, and Map tabs
- **TreeListView**: @Query fetches trees, search filters by species/variety/notes, triggers CaptureTreeView and ExportView
- **TreeMapView**: MapKit with tree annotations, toolbar toggle to show variety instead of species
- **CaptureTreeView**: Live GPS accuracy, collection picker (defaults to last used via @AppStorage), photo picker
- **TreeDetailView**: @Bindable tree for inline editing, collection assignment, embedded map, photo gallery
- **CollectionListView**: List all collections, create new, import from JSON
- **CollectionDetailView**: View/edit collection, add/remove trees, export collection

### Export/Import System
Three exporters in `Services/Exporters/` produce file URLs for sharing (accept optional `filePrefix` for collection exports):
- **CSVExporter**: Spreadsheet format with all tree fields
- **JSONExporter**: Full data with optional base64-encoded photos
- **GPXExporter**: Standard GPS waypoint format for mapping apps

Import via **ImportCollectionView**: parses JSON exports into new or existing collections.

### UI Components
- **AccuracyBadge**: Color-coded accuracy display (green < 5m, yellow < 15m, red > 15m)
- **ImagePicker**: UIImagePickerController wrapper for camera/library
- **PhotoGalleryView**: Grid display with fullscreen viewer
