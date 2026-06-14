# Lingua Player

A native macOS app for learning English through video — open MKV files with multiple audio + subtitle tracks, switch languages on the fly, and get AI-powered contextual translations per subtitle phrase.

See [`CLAUDE.md`](./CLAUDE.md) for the full product brief.

## Requirements

- macOS 13 Ventura or later
- Xcode 15+ (Swift 5.9+)
- VLCKit (resolved via Swift Package Manager — added as a project dependency)

## Getting Started

1. Open `LinguaPlayer.xcodeproj` in Xcode.
2. Wait for Xcode to resolve the VLCKit Swift Package dependency.
3. Select the `LinguaPlayer` scheme and press ⌘R to run.

### About the VLCKit dependency

The project references VLCKit at:

```
https://code.videolan.org/videolan/VLCKit.git  (branch: master)
```

If Xcode fails to resolve this as a Swift Package (VLCKit's SPM support has shifted across releases), update the URL or version requirement in **Project → Package Dependencies** to a known-good SPM-compatible fork or tagged release.

## Current Status

Step 1 of the roadmap is implemented:

- App launches with an **Open Video…** button (⌘O).
- Picks files via `NSOpenPanel`, filtered to common video types (`mkv`, `mp4`, `mov`, `m4v`, `avi`).
- Probes the selected file with VLCKit and lists every audio and subtitle track it discovers (index, language, codec, description).

Playback, subtitle parsing, audio toggling, phrase navigation, and AI translation are scheduled for later steps — see `CLAUDE.md`.
