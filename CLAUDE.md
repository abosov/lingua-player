# Lingua Player — macOS App for Language Learning Through Video

## Project Vision

A native macOS application for learning English through video content. The user opens an MKV file containing multiple audio tracks (English original + Russian dub) and subtitle tracks, then watches the video while switching between audio languages, reading subtitles, and getting AI-powered contextual translations of individual phrases.

The core idea: subtitles define "phrases". Each subtitle cue (with its start/end timecodes) is one phrase. All navigation, translation, and playback logic revolves around this concept.

## Tech Stack

- **Platform:** macOS 13+ (Ventura and later), native app
- **Language:** Swift 5.9+
- **UI Framework:** SwiftUI (AppKit only where SwiftUI lacks capability)
- **Video Engine:** VLCKit (via CocoaPods or SPM) — chosen because AVFoundation does not natively support MKV containers, multiple audio track switching, or embedded subtitle extraction reliably
  - VLCKitSPM 4.x crashes on Intel Macs (OpenGL 2.1). Using VLCKit 3.x via tylerjonesio/vlckit-spm instead.
- **AI Translation:** Anthropic Claude API (claude-sonnet-4-6) via direct REST calls (URLSession), no SDK dependency
- **Build System:** Xcode, Swift Package Manager preferred for dependencies
- **Minimum deployment target:** macOS 13.0

## Core Features (MVP)

### 1. File Open & Stream Discovery
- User opens an MKV file via standard macOS Open dialog or drag-and-drop onto the app window
- App probes the file using VLCKit and extracts all available streams:
  - Audio tracks (list with index, language tag, codec info)
  - Subtitle tracks (list with index, language tag, format)
- App presents a configuration screen where the user assigns:
  - **Primary audio (Channel A):** intended for the English original track
  - **Secondary audio (Channel B):** intended for the Russian dubbed track
  - **Active subtitles:** intended for the English subtitle track (this is the "phrase source")
- The app remembers this mapping per file (persist in UserDefaults or a JSON sidecar)

### 2. Video Playback with Dual Audio Toggle
- Standard video player controls: play/pause, seek bar, volume, fullscreen
- A prominent toggle button (or keyboard shortcut, e.g. `Tab`) to switch between Channel A and Channel B instantly
- Visual indicator showing which channel is currently active ("EN" / "RU")
- Switching must be instantaneous — no reload, no stutter

### 3. Subtitle Display
- The active English subtitle track is rendered as an overlay at the bottom of the video
- Current phrase is highlighted/visible; previous and next phrases may optionally be shown dimmed
- Subtitles are parsed into an ordered array of cues: `[{index, start, end, text}]`
- This array is the backbone for phrase navigation

### 4. Phrase Navigation
- **"Previous phrase" button (and keyboard shortcut, e.g. `←`):** seeks to the start time of the previous subtitle cue
- **"Repeat phrase" button (and shortcut, e.g. `↓`):** seeks to the start time of the current subtitle cue (replays it)
- **"Next phrase" button (and shortcut, e.g. `→`):** seeks to the start time of the next subtitle cue
- Playback auto-resumes after seeking

### 5. AI Contextual Translation
- A "Translate" button (and shortcut, e.g. `T`) sends the current phrase to Claude API
- The prompt includes:
  - The current subtitle text
  - 2 previous and 2 next subtitle texts (for context)
  - Instruction: "Translate this English phrase to Russian. Provide: 1) natural translation, 2) word-by-word breakdown of difficult words, 3) brief grammar notes if relevant. Consider the surrounding context."
- Response is displayed in a panel (sidebar or overlay) next to the video
- Translation panel persists until dismissed or a new translation is requested

## Architecture Principles

- **Single-window app.** One main window: video + controls + subtitle overlay + translation panel.
- **MVVM.** Views are SwiftUI. Business logic lives in ObservableObject view models. VLCKit interaction is wrapped in a `VideoPlayerEngine` service class.
- **No network except AI.** The app works fully offline for playback. Network is only used for Claude API translation calls.
- **Keyboard-first.** Every action has a keyboard shortcut. The app should be usable without touching the mouse during playback.

## File Structure (Target)

```
lingua-player/
├── CLAUDE.md                  # This file
├── .gitignore
├── LinguaPlayer.xcodeproj/    # or Package.swift if pure SPM
├── LinguaPlayer/
│   ├── App/
│   │   └── LinguaPlayerApp.swift
│   ├── Models/
│   │   ├── SubtitleCue.swift          # struct: index, start, end, text
│   │   ├── StreamMapping.swift        # which tracks are assigned to A/B/subs
│   │   └── TranslationResult.swift    # AI response model
│   ├── Services/
│   │   ├── VideoPlayerEngine.swift    # VLCKit wrapper
│   │   ├── SubtitleParser.swift       # parse VLCKit subtitle events into [SubtitleCue]
│   │   └── TranslationService.swift   # Claude API client
│   ├── ViewModels/
│   │   ├── PlayerViewModel.swift      # playback state, audio toggle, phrase nav
│   │   └── StreamSetupViewModel.swift # file open, stream discovery, mapping
│   ├── Views/
│   │   ├── MainPlayerView.swift       # video + overlay + controls
│   │   ├── StreamSetupView.swift      # track selection screen
│   │   ├── SubtitleOverlayView.swift  # subtitle rendering
│   │   ├── TranslationPanelView.swift # AI translation display
│   │   └── ControlBarView.swift       # playback + phrase nav buttons
│   └── Resources/
│       └── Assets.xcassets
└── README.md
```

## Current Step

**Step 1: Project scaffold + VLCKit integration + file open + stream discovery.**

Create the Xcode project (macOS app, SwiftUI lifecycle), integrate VLCKit, implement file open (NSOpenPanel for .mkv/.mp4), probe the opened file for audio and subtitle tracks, and display the discovered tracks in a simple list UI. No playback yet — just open, scan, and show what's inside the file.

Acceptance criteria for Step 1:
- App launches with a "Open Video" button
- Clicking it opens a file picker filtered to video files (.mkv, .mp4, .avi)
- After selecting a file, the app displays:
  - List of audio tracks (index, language, codec)
  - List of subtitle tracks (index, language, format)
- No crashes, no hardcoded paths

## API Keys & Secrets

- Claude API key must NEVER be committed to git
- Store in a `Secrets.xcconfig` file (git-ignored) or read from environment variable / macOS Keychain
- The `.gitignore` already covers `*.xcconfig` patterns — verify this

## Coding Conventions

- Swift naming conventions (camelCase properties, PascalCase types)
- Prefer `struct` over `class` where possible
- Use Swift concurrency (async/await) for API calls
- Minimize force unwraps — use guard/let and proper error handling
- Comments in English
