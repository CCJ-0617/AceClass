# Contributing to AceClass

Thanks for contributing to AceClass.

This project is a macOS SwiftUI application. The most useful contributions are:

- bug fixes
- UX improvements
- playback and persistence reliability improvements
- tests for data and state management
- documentation cleanup

## Before You Start

Please read:

- [README.md](README.md)
- [USER_GUIDE.md](USER_GUIDE.md)
- [DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md)
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- [SECURITY.md](SECURITY.md)

## Development Setup

Requirements:

- macOS 15.4 or later
- Xcode 16 or later
- Git

Recommended setup:

1. Clone the repository.
2. Run `sh scripts/setup-git-hooks.sh`.
3. Open `AceClass.xcodeproj` in Xcode.
4. Build and run the `AceClass` target.

The pre-commit hook blocks common private content and local machine artifacts from being committed.

## Project Conventions

### Source of Truth

- Keep user-facing project entry content in `README.md`.
- Keep end-user instructions in `USER_GUIDE.md`.
- Keep architecture and maintenance details in `DEVELOPER_GUIDE.md`.
- Do not duplicate large sections across those files.

### Code Style

- Prefer small, focused changes.
- Keep SwiftUI view logic readable and avoid unnecessary abstraction.
- Follow existing naming and file organization unless there is a clear cleanup benefit.
- Preserve sandbox-safe file access patterns.
- Do not commit user-specific Xcode state or local machine files.

### UI and Language

- Documentation is in English.
- The current app UI still contains Traditional Chinese copy in several places.
- If you update UI strings, try to keep terminology consistent across the app.

## Testing

Before opening a pull request, do as much of the following as applies:

- build the app in Xcode
- run unit tests
- run UI tests if your change affects flows they cover
- manually verify folder selection, course scanning, playback, and metadata persistence when relevant

If you could not run part of the validation, say so in the pull request.

## Pull Requests

Open a pull request with:

- a clear summary
- the reason for the change
- screenshots or short recordings for UI changes
- testing notes
- known limitations or follow-up work

Keep pull requests focused. Separate unrelated cleanup from functional changes.

## Commit Hygiene

Before committing:

- review `git diff --cached`
- make sure no secrets or private local paths are staged
- make sure `.DS_Store`, `xcuserdata`, logs, and local signing files are not included

If the hook blocks a commit, fix the staged content rather than bypassing the check.

## Reporting Bugs

When reporting a bug, include:

- macOS version
- AceClass version or branch
- exact reproduction steps
- expected behavior
- actual behavior
- screenshots or logs if relevant

Use the issue templates in `.github/ISSUE_TEMPLATE` when possible.

## Security Issues

Do not open a public issue for a security-sensitive problem. Follow [SECURITY.md](SECURITY.md) instead.
