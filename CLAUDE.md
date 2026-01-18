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
- **Tree** (@Model): SwiftData entity storing GPS coordinates, accuracy, species, notes, and photos (as JPEG Data blobs with external storage)
- **LocationManager** (@Observable): Wraps CLLocationManager with `kCLLocationAccuracyBest` for precise GPS capture
- **SwiftData ModelContainer**: Configured in TreesApp.swift, injected via environment

### View Hierarchy
- **ContentView**: TabView with List and Map tabs
- **TreeListView**: @Query fetches trees, NavigationStack with search, triggers CaptureTreeView and ExportView sheets
- **TreeMapView**: MapKit with tree annotations, user location, triggers CaptureTreeView sheet
- **CaptureTreeView**: Live GPS accuracy display, captures location when accuracy < 20m, photo picker
- **TreeDetailView**: @Bindable tree for inline editing, embedded map, photo gallery

### Export System
Three exporters in `Services/Exporters/` produce file URLs for sharing:
- **CSVExporter**: Spreadsheet format
- **JSONExporter**: Full data with optional base64-encoded photos
- **GPXExporter**: Standard GPS waypoint format for mapping apps

### UI Components
- **AccuracyBadge**: Color-coded accuracy display (green < 5m, yellow < 15m, red > 15m)
- **ImagePicker**: UIImagePickerController wrapper for camera/library
- **PhotoGalleryView**: Grid display with fullscreen viewer
