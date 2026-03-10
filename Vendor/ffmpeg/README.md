# Bundled ffmpeg Binaries

This directory stores vendored `ffmpeg` binaries that AceClass can bundle into the app at build time.

Current binary:

- `ffmpeg-arm64`
  - Source: `https://github.com/eugeneware/ffmpeg-static/releases/download/b6.1.1/ffmpeg-darwin-arm64`
  - SHA-256: `a90e3db6a3fd35f6074b013f948b1aa45b31c6375489d39e572bea3f18336584`
  - Verified on 2026-03-10 with `shasum -a 256`

Build behavior:

- `scripts/bundle-ffmpeg.sh` prefers `Vendor/ffmpeg/ffmpeg-arm64` on Apple Silicon builds.
- `Vendor/ffmpeg/ffmpeg-x86_64` can be added later for Intel-specific builds.
- `Vendor/ffmpeg/ffmpeg` remains a generic fallback name if a universal binary is introduced.
