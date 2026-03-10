# AceClass User Guide

## What AceClass Does

AceClass helps you organize recorded class videos on macOS. After you select a root folder, the app scans each child folder as a course, lists supported video files such as `.mp4`, `.mov`, `.m4v`, `.mkv`, `.avi`, `.mpeg`, `.mts`, and `.3gp`, remembers what you watched, and lets you assign a target date to each course.

## System Requirements

- macOS 15.4 or later
- A folder structure where each course is stored in its own subfolder
- Video files in supported formats: `.mp4`, `.mov`, `.m4v`, `.mkv`, `.avi`, `.mpg`, `.mpeg`, `.mts`, `.m2ts`, `.ts`, `.3gp`, `.3g2`
- For `.mkv`, AceClass may prepare a compatible local playback copy before starting playback using its built-in converter

## Recommended Folder Structure

```text
Course Root/
├── Biology/
│   ├── 20250101_Introduction.mp4
│   └── 20250108_CellDivision.mp4
├── Literature/
│   └── 20250103_WorldWarII.mp4
└── Chemistry/
    └── 20250105_ReactionRates.mp4
```

Recommendations:

- Keep one course per folder.
- Use descriptive filenames.
- If you include dates in filenames, use `YYYYMMDD` for stable sorting.
- Avoid unsupported video formats if you want the app to detect files automatically.

## First Launch

1. Open the app.
2. Click `Select Folder`.
3. Choose the root folder that contains all course subfolders.
4. Grant macOS file access when prompted.

Once a folder is selected, AceClass stores a security-scoped bookmark so it can reopen the same location later.

## Main Workflow

### Browse Courses

- The left sidebar shows every detected course folder.
- Select a course to load its video list.
- If no videos appear, verify that the folder contains one of the supported video formats.

### Play Videos

- Click a video row to start playback.
- Use `Control + Command + F` to toggle full screen.
- AceClass remembers the last playback position for each video.
- When playback reaches roughly 75%, the app automatically marks the video as watched.

### Edit Video Metadata

Each video row supports lightweight metadata updates:

- Display name
- Note text
- Manual watched or unwatched toggle

These changes are saved locally and may also be copied to `videos.json` in the course folder.

## Countdown Center

The toolbar provides access to the Countdown Center, where you can manage course deadlines.

### What You Can Do There

- Set or clear a target date for a course
- Add a short target description
- Filter courses with deadlines
- Sort by remaining days or course name
- Review overdue and upcoming work from one screen

### Deadline Status

- Blue: healthy buffer
- Orange: due soon
- Red: overdue

### Quick Presets

The editor includes preset buttons for:

- 7 days
- 14 days
- 30 days
- 60 days
- 90 days
- 180 days

## How Data Is Stored

AceClass uses a local-first storage model.

### Local Metadata

The app stores course metadata and video metadata inside the app's Application Support directory. In a sandboxed macOS app, this resolves inside the app container.

Stored data includes:

- watched state
- notes
- display names
- last playback position
- course target date
- course target description

### External Sync

AceClass can also copy video metadata to `videos.json` inside each course folder. This is best-effort sync only.

Important:

- Local storage is the primary source of truth.
- Countdown metadata stays local.
- External writes can fail if the drive is unavailable or permissions change.

## Privacy and Permissions

AceClass is designed around explicit file access:

- It only reads folders you choose.
- It does not scan arbitrary parts of your disk.
- It stores app data locally on your Mac.
- It does not document any telemetry or remote account requirement in the current codebase.

## Troubleshooting

### No Courses Appear

Check the following:

- The selected folder is the course root, not a single course folder.
- Each course is inside its own child folder.
- The child folders contain `.mp4` files.
- macOS access permission was granted.

If needed, reselect the folder from the sidebar button.

### A Video Does Not Play

Check the following:

- The file is a valid video file.
- The file is not corrupted.
- The external drive is still connected.
- The app still has permission to the folder.
- If it is an `.mkv`, wait a moment for AceClass to prepare the built-in compatibility copy before playback starts.

### Watch Status Looks Wrong

AceClass can change watched state in two ways:

- manual toggle in the list
- automatic mark after about 75% playback

If a video was marked watched earlier than expected, replay it and toggle the state manually.

### Resume Playback Did Not Restore

Possible causes:

- The app closed before the latest playback position was flushed to disk.
- The file path changed.
- The video was nearly finished already, so resume was intentionally skipped.

### Deadline Data Is Missing

Course deadlines are stored locally per Mac. They are not designed as cross-device synced data.

## Debug Console

AceClass includes a debug console in the toolbar. It is primarily for diagnostics and development, but it can help you confirm that:

- the folder scan succeeded
- metadata files were saved
- cache activity happened
- playback initialization completed

## FAQ

### Does AceClass support multiple devices?

Partially. Video metadata may sync back to course folders through `videos.json`, but local-only metadata such as countdown targets is machine-specific.

### Does AceClass support subtitles?

The codebase contains a local transcription pipeline, but it is currently behind a runtime flag and should be treated as an internal or experimental capability.

### Can I uninstall and keep my metadata?

Your original videos remain in their folders. Local app metadata may be removed when the app container is removed, so keep that in mind before reinstalling or deleting the app.
