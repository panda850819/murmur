# Murmur

Voice → text dictation for macOS + iOS. Personal dogfood tool, not a product launch.

**Status**: pre-MVP scaffold (Sprint 2, 2026-05-11). Hard kill date `2026-08-11`.

This repo is the successor to [`panda850819/murmur-voice`](https://github.com/panda850819/murmur-voice)
(Tauri + Rust, macOS+Windows desktop), which continues in bug-fix mode until this
repo has a dogfoodable iOS TestFlight build. See [`BRIEF.md`](./BRIEF.md) for the
full scope cap, kill criteria, and pivot rationale.

## Frame

- Personal practice repo: learn modern Apple stack (Swift / SwiftUI / WhisperKit)
  AND practice the product-building flow (BRIEF / ROADMAP / dogfood loop / release / retro)
- Dogfood circle: Panda + Yei/Sommet + friends. **Not for general use, not actively promoted**
- **No differentiation claim** — VoiceInk, openquack, typeless, superwhisper all overlap

## Stack

| Layer | Choice |
|---|---|
| Language | Swift 5.10+ |
| UI | SwiftUI (macOS + iOS), no AppKit, no Catalyst |
| Code sharing | Swift Package (`MurmurCore`) |
| Transcription (on-device) | [WhisperKit](https://github.com/argmaxinc/WhisperKit) (MIT, pinned `1.0.0`) |
| Transcription (cloud fallback) | Groq Whisper API |
| LLM enhance | Groq chat completions |
| Audio capture | AVAudioEngine |
| Distribution | TestFlight (iOS) + signed DMG (macOS) |

## Repo layout

```
murmur/
├── BRIEF.md                       scope cap, kill criteria, stack lock
├── ROADMAP.md                     long-term wishlist (BRIEF wins on conflict)
├── project.yml                    XcodeGen spec — generates Murmur.xcodeproj
├── scripts/
│   └── patch-xcodeproj.py         XcodeGen 2.45.4 local-pkg linkage workaround
├── Sources/MurmurMac/             Xcode macOS app target (.app, Info.plist, entitlements)
├── Core/
│   ├── Package.swift              SwiftPM library (MurmurCore + WhisperKit dep)
│   ├── Sources/MurmurCore/        shared logic (also future iOS target dep)
│   └── Tests/MurmurCoreTests/     library tests
├── docs/
│   ├── briefs/                    office-hours outputs
│   └── sessions/                  sprint artifacts
├── Inbox/                         PAUSED sprint checkpoints
└── .github/workflows/ci.yml       swift build + swift test on macos-15
```

## Build

The core library + tests build via SwiftPM:

```bash
cd Core
swift build         # build MurmurCore library
swift test          # run MurmurCoreTests
```

The macOS app builds via Xcode (Sprint 3 infra in progress — see
`Inbox/sprint-murmur-sprint-3-xcode-audio-2026-05-14.md`):

```bash
xcodegen generate                          # produce Murmur.xcodeproj
python3 scripts/patch-xcodeproj.py         # XcodeGen bug workaround
open Murmur.xcodeproj                      # build & run from Xcode
```

Requires Xcode 16+ (Swift 6+) on macOS 14+. WhisperKit v1.0.0 uses
Swift 6 `@retroactive` attribute + macOS 14 `MLState` Core ML API.

## MVP v0.1 (scope-capped, see BRIEF)

macOS only, one button, one flow:

- press hotkey → record (AVAudioEngine) → WhisperKit on-device transcribe → paste foreground app
- Groq cloud fallback when local model unavailable or offline
- Groq LLM cleanup (optional, default on)

v0.1 ships before any v0.2 issue is opened. No Glossary, no Power Mode, no
Personal Dictionary, no second settings tab in v0.1.

## License

TBD. Not chosen yet because frame = personal dogfood. Will pick before any
external user is invited.

## Inspiration (UX patterns only, NO code copy)

- [VoiceInk](https://github.com/Beingpax/VoiceInk) (GPL v3, macOS AppKit) — Power Mode / Personal Dictionary / hotkey UX. **Code copy explicitly disallowed** in `BRIEF.md` due to GPL contagion.
- [openquack](https://github.com/larryxiao/openquack) (MIT) — menu-bar UX + WhisperKit integration patterns
- [WhisperKit demo apps](https://github.com/argmaxinc/WhisperKit) — iOS audio capture + Core ML pipeline reference
