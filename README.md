# AceClass

AceClass is a macOS SwiftUI app for managing recorded class videos stored in folders on local or external drives. It scans course folders, tracks watch progress, saves notes and resume positions, and lets you assign deadlines to each course.

## Highlights

- Scan a root folder and treat each child folder as a course.
- Play common video formats such as `.mp4`, `.mov`, `.m4v`, `.avi`, `.mpeg`, `.mts`, and `.3gp` with a native macOS player and full-screen support.
- Open `.mkv` files through an automatic compatibility-preparation step when native playback is unavailable, using the converter bundled inside the app.
- Track watched status, notes, and last playback position per video.
- Auto-mark a video as watched after roughly 75% playback progress.
- Manage course deadlines in the Countdown Center.
- Store metadata locally with best-effort `videos.json` sync back to course folders.
- Inspect runtime logs through the built-in debug console.

## Requirements

- macOS 15.4 or later
- Xcode 16 or later for development
- Course videos stored in one of the supported formats: `.mp4`, `.mov`, `.m4v`, `.mkv`, `.avi`, `.mpg`, `.mpeg`, `.mts`, `.m2ts`, `.ts`, `.3gp`, `.3g2`

## Folder Layout

AceClass expects one root folder that contains one subfolder per course.

```text
Courses/
├── Math/
│   ├── 20250101_Intro.mp4
│   ├── 20250103_Chapter1.mp4
│   └── videos.json
├── English/
│   ├── 20250102_Grammar.mp4
│   └── videos.json
└── Physics/
    └── 20250105_Lab.mp4
```

The app reads videos from the selected root folder, keeps primary metadata in the app sandbox, and may copy video metadata back to `videos.json` inside each course folder.

## Getting Started

### Run the App

1. Open `AceClass.xcodeproj` in Xcode.
2. Build and run the `AceClass` target.
3. Click `Select Folder` and choose your course root folder.
4. Pick a course from the sidebar, then choose a video to start playback.

### Daily Workflow

1. Select a source folder.
2. Browse courses in the left sidebar.
3. Play videos from the center list.
4. Use the Countdown Center from the toolbar to set or review course deadlines.
5. Reopen videos later and continue from the saved playback position.

## Documentation

- [USER_GUIDE.md](USER_GUIDE.md): end-user setup, workflow, storage behavior, and troubleshooting
- [DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md): architecture, data flow, persistence, playback pipeline, and development notes
- [CONTRIBUTING.md](CONTRIBUTING.md): contribution workflow and repository conventions
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md): community participation expectations
- [SECURITY.md](SECURITY.md): responsible disclosure guidance
- [SUPPORT.md](SUPPORT.md): support and issue routing

## Repository Layout

```text
AceClass/
├── .github/                  # Issue and pull request templates
├── AceClass/                 # App source
├── AceClassTests/            # Unit tests
├── AceClassUITests/          # UI tests
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── SECURITY.md
├── SUPPORT.md
├── LICENSE
├── README.md
├── USER_GUIDE.md
└── DEVELOPER_GUIDE.md
```

## Notes

- The current UI is written primarily in Traditional Chinese; the documentation is now English.
- Speech-to-caption code exists in the codebase, but the captions UI is currently gated by a runtime flag and is not a core documented user feature.
- `.mkv` playback is handled by a bundled compatibility converter inside the built app. The repository now vendors an `arm64` `ffmpeg` binary for Apple Silicon builds, and the build script still bundles any required non-system dylibs when needed.
- Metadata is stored locally first. External folder sync is best effort and should not be treated as the only source of truth.

## Community

Contributions are welcome. Before opening a pull request, please review:

- [CONTRIBUTING.md](CONTRIBUTING.md)
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- [SECURITY.md](SECURITY.md)

GitHub issue and pull request templates are available under `.github/`.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
