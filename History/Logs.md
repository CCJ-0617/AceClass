# Logs

## August 9, 2025

### Fixes and Updates
1. **VideoPlayerView.swift**
   - Fixed SwiftUI compile error by moving `.frame` modifier inside each `#if/#else` branch.

2. **LocalTranscription.swift**
   - Added `onDeviceCapableLocales` to filter locales that support on-device recognition.
   - Fixed `Cannot find 'LSeg' in scope` by defining `LSeg` at class scope.
   - Resolved Swift warning by changing `var last` to `let last` in the coalescing loop.
   - Hardened transcription logic to avoid kAFAssistantErrorDomain 1101 errors by ensuring only on-device capable locales are used.

3. **AppState.swift**
   - Adjusted `selectVideo` to handle multilingual captions (Chinese + English) and ensure proper security-scoped resource access.

### Debugging Notes
- Addressed sandbox-related errors and ensured proper entitlement configurations.
- Recommended enabling Dictation and downloading language packs for Chinese (Traditional) and English to avoid transcription errors.