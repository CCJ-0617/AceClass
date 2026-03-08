# AceClass Developer Guide

## Overview

AceClass is a macOS SwiftUI application for browsing course folders, playing local videos, tracking progress, and managing per-course deadlines. The app is local-first, sandbox-aware, and built around a single shared `AppState` object.

Core responsibilities:

- scan a user-selected root folder
- treat each child folder as a course
- persist video and course metadata locally
- play videos safely from sandboxed locations
- save last playback position and watched state
- manage deadline data through the Countdown Center

## Tech Stack

- SwiftUI
- AVKit
- Combine
- Foundation
- Speech framework for the optional local transcription pipeline

Project target:

- macOS 15.4

## Repository Structure

```text
AceClass/
├── AceClass/
│   ├── AceClassApp.swift
│   ├── AppState.swift
│   ├── Models.swift
│   ├── ContentView.swift
│   ├── LocalMetadataStorage.swift
│   ├── VideoPlayerView.swift
│   ├── CountdownCenterView.swift
│   ├── CourseRowView.swift
│   ├── VideoRowView.swift
│   ├── CourseStatisticsView.swift
│   ├── Logger.swift
│   ├── VideoCacheManager.swift
│   └── LocalTranscription.swift
├── AceClassTests/
├── AceClassUITests/
├── README.md
├── USER_GUIDE.md
└── DEVELOPER_GUIDE.md
```

## Application Model

### Entry Point

[AceClassApp.swift](AceClass/AceClassApp.swift) creates a single `WindowGroup` with `ContentView` and adds a keyboard shortcut for full-screen toggle.

### State Container

[AppState.swift](AceClass/AppState.swift) is the runtime hub. It owns:

- loaded courses
- selected course and selected video
- shared `AVPlayer`
- source folder bookmark state
- countdown-derived data
- playback resume state
- caption loading state
- cache and logging side effects

`AppState` is annotated with `@MainActor`, which keeps UI-facing mutations on the main thread. Expensive work is deferred through async tasks.

## Data Model

### `VideoItem`

Defined in [Models.swift](AceClass/Models.swift).

Important fields:

- `id`
- `fileName`
- `displayName`
- `note`
- `watched`
- `date`
- `lastPlaybackPosition`

Notes:

- The date is parsed from the filename using a regex that supports `YYYYMMDD` and two-digit-year forms.
- `lastPlaybackPosition` is optional and persists resume state.

### `Course`

Also defined in [Models.swift](AceClass/Models.swift).

Important fields:

- `id`
- `folderURL`
- `videos`
- `targetDate`
- `targetDescription`

Computed helpers include:

- `daysRemaining`
- `isOverdue`
- `countdownText`

## Persistence Strategy

### Local-First Metadata

[LocalMetadataStorage.swift](AceClass/LocalMetadataStorage.swift) writes metadata under the app's Application Support directory.

Data is split into:

- video metadata JSON per course storage key
- course metadata JSON per course storage key

Storage keys are derived from a normalized course path plus a short SHA-256 digest, which gives stable filenames across runs while avoiding raw path leakage in filenames.

### External Folder Sync

The app can copy video metadata back to `videos.json` inside the course folder. This behavior is:

- best effort
- throttled
- not the primary source of truth

Countdown metadata remains local.

## Folder Access and Sandboxing

AceClass relies on security-scoped bookmarks to reopen user-selected folders across launches.

Key points in [AppState.swift](AceClass/AppState.swift):

- bookmark load at startup
- security-scoped access when the user selects a folder
- separate access tracking for the currently playing video
- cleanup in `deinit`

This is central to keeping external-drive playback working in a sandboxed macOS app.

## UI Structure

### `ContentView`

[ContentView.swift](AceClass/ContentView.swift) uses `NavigationSplitView` with three areas:

- course sidebar
- video list
- detail pane for player or course statistics

Toolbar actions currently open:

- debug console
- Countdown Center

The current code uses both a calendar button and a gear button for the Countdown Center sheet.

### Course and Video Views

Supporting views:

- [CourseRowView.swift](AceClass/CourseRowView.swift)
- [VideoRowView.swift](AceClass/VideoRowView.swift)
- [CourseStatisticsView.swift](AceClass/CourseStatisticsView.swift)
- [UnwatchedVideoRowView.swift](AceClass/UnwatchedVideoRowView.swift)

### Countdown UI

Countdown-related views:

- [CountdownCenterView.swift](AceClass/CountdownCenterView.swift)
- [CountdownSettingsView.swift](AceClass/CountdownSettingsView.swift)
- [CountdownDisplay.swift](AceClass/CountdownDisplay.swift)

The current primary editor flow is the Countdown Center sheet.

## Playback Pipeline

### Selection and Debounce

Video selection is intentionally debounced in `AppState` to avoid churn during rapid user interaction and to reduce benign cancellation noise while the player is being initialized.

### Shared Player

A single shared `AVPlayer` instance is owned by `AppState` and rendered by [VideoPlayerView.swift](AceClass/VideoPlayerView.swift).

On macOS, the app uses an AppKit-backed `AVPlayerView` wrapper rather than relying entirely on the SwiftUI `VideoPlayer`.

### Resume Playback

Playback progress is sampled periodically:

- last playback position is updated in memory
- writes are debounced
- the last known position is restored when reopening a video
- resume is skipped when the saved position is too small or too close to the end

### Auto-Mark Watched

If playback reaches roughly 75% of the video duration, the app marks the video as watched and saves immediately.

### Local Video Cache

[VideoCacheManager.swift](AceClass/VideoCacheManager.swift) can prepare a cached local copy for playback. This reduces repeated reads from external storage for smaller assets and exposes cache stats to the debug console.

## Countdown Logic

`AppState` builds derived arrays for:

- all courses with targets
- upcoming deadlines
- overdue courses

This keeps view logic simple and avoids recomputing expensive filtering in multiple places.

Course urgency is based on `daysRemaining`:

- overdue if negative
- soon when the remaining days are small
- normal otherwise

The UI currently uses color to communicate this state.

## Logging and Diagnostics

[Logger.swift](AceClass/Logger.swift) provides:

- in-memory log entries for the debug console
- batched log writes to disk
- log rotation
- runtime severity filtering
- cache visibility in the console UI

This is the main diagnostics surface for folder scanning, playback initialization, metadata writes, and transcription behavior.

## Local Transcription Pipeline

[LocalTranscription.swift](AceClass/LocalTranscription.swift) contains a fairly involved local transcription pipeline.

Capabilities in the current code:

- locale filtering for supported recognizers
- optional cloud fallback
- audio preparation and analysis
- forced segmentation for long media
- timeout-based recognition attempts
- multi-locale merge of caption segments

Important limitation:

- caption UI is currently behind `captionsFeatureEnabled`, which defaults to `false` in `AppState`

That means the code exists, but it is not currently a guaranteed end-user feature.

## Build and Run

1. Open the Xcode project.
2. Select the `AceClass` scheme.
3. Build and run on macOS 15.4 or later.
4. Grant folder access when prompted.

There is no separate backend or service dependency in the current repository.

## Testing

The repository contains:

- [AceClassTests.swift](AceClassTests/AceClassTests.swift)
- [AceClassUITests.swift](AceClassUITests/AceClassUITests.swift)
- [AceClassUITestsLaunchTests.swift](AceClassUITests/AceClassUITestsLaunchTests.swift)

At the moment, the codebase appears to rely heavily on manual verification for folder access, playback, external-drive behavior, and speech recognition.

## Known Gaps

- UI copy is still mostly Traditional Chinese.
- `ContentView` currently exposes two toolbar buttons that open the same Countdown Center sheet.
- Some historic documentation previously duplicated large blocks of user guide content and version notes; this guide intentionally avoids that pattern.
- Speech recognition behavior depends on the local macOS speech stack and installed language support.

## Documentation Policy

The repository now treats documentation as three separate surfaces:

- `README.md` for project entry
- `USER_GUIDE.md` for end users
- `DEVELOPER_GUIDE.md` for maintainers and contributors

Keep those responsibilities separate. Do not reintroduce large duplicated sections across files.
