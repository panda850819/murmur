---
date: 2026-05-11
type: sprint
state: SHIPPED
topic: murmur-voiceink-repo-bootstrap
mode: default
iteration: 2
persona: pandastack:eng-lead
tags: [sprint, shipped, scaffold, swift, swiftui, whisperkit]
---

# Sprint — murmur repo bootstrap — 2026-05-11

## Capability probe

```
[1] AGENTS substrate    : ok    (~/.claude/CLAUDE.md present)
[2] vault root          : ok    (brain — Sprint 1 entries already there)
[3] lib/ files          : ok
[4] persona skills      : ok    (eng-lead)
[5] cli tools           : ok    (Xcode 26.3, Swift 6.2.4, gh 2.92.0 SSH auth)
[6] write paths         : ok    (/Users/panda/site/apps/ writable, 164Gi free)
[7] Sprint 1 gate       : ok    (BRIEF draft at murmur-voice@0902f10)
[8] WhisperKit upstream : ok    (v1.0.0, 10 days old)
```

## Stage progression

| Stage | Status | Output |
|---|---|---|
| 0 probe | ok | 8 checks green |
| 1 dojo | done | new territory (no prior Swift in brain), WhisperKit v1.0.0 fresh — pin exact |
| 2 grill | done | repo name = `murmur` / GitHub public / done criteria = build green + push |
| 3 execute | done iter 1 | scaffold + WhisperKit dep + swift build 38.85s + tests 2/2 |
| 4 review | done iter 2 | P1-a (LICENSE) patched, SD-a (ROADMAP) accepted |
| 5 ship gate | SHIPPED | commit + GitHub create + push |
| 6 terminal | SHIPPED | first CI run queued, watching |

## Findings (review)

```
Iteration 1: P0=0 / P1=1 / COVERAGE GAP=0 / SCOPE DRIFT=1 (borderline)
  P1-a [LICENSE]: PATCHED — LICENSE.md placeholder added ("TBD, all rights
    reserved until external user invite")
  SD-a [ROADMAP]: ACCEPTED — kept (1-page stub, parked ideas, not removable
    without rewriting later)

Iteration 2: P0=0 / P1=0 / COVERAGE GAP=0 / SCOPE DRIFT=0  → clean
```

## Gate log

- Stage 2 grill: repo name `murmur` (over `murmur-voice-app` / `murmur-swift` / `voice`), GitHub public (matches old murmur-voice), done criteria = build green + push
- Stage 4 review: approve + patch LICENSE, accept ROADMAP

## Outcomes

### Repo

- Local: `/Users/panda/site/apps/murmur/`
- GitHub: https://github.com/panda850819/murmur (public)
- Initial commit: `84444c3` (root-commit, 11 files, 541 lines)
- CI: workflow queued on first push (see `.github/workflows/ci.yml`)

### Layout shipped

```
murmur/
├── BRIEF.md                  copied from murmur-voice draft, header updated
├── README.md                 frame, stack table, build commands
├── ROADMAP.md                stub (v0.1 / v0.2 / v0.3+ parked)
├── LICENSE.md                placeholder, "TBD before external user invite"
├── .gitignore                Swift / Xcode / DerivedData conventions
├── Package.swift             swift-tools 5.10, macOS 14+, WhisperKit exact 1.0.0
├── Package.resolved          committed (app, not library — locks deps)
├── Sources/
│   ├── MurmurCore/Murmur.swift       version + whisperKitReachable()
│   └── MurmurMac/MurmurApp.swift     SwiftUI @main, ContentView, #Preview
├── Tests/MurmurCoreTests/MurmurCoreTests.swift   2 tests
└── .github/workflows/ci.yml  swift build + swift test on macos-14
```

### Verified

- `swift build` → 38.85s clean, 0.29s incremental → green
- `swift test` → 2/2 pass in 0.002s
- WhisperKit v1.0.0 resolved + linked + symbol reachable at runtime
- GitHub repo public, initial push successful, CI workflow triggered

### Stack decisions (locked, mirrors BRIEF)

| Layer | Choice |
|---|---|
| swift-tools-version | 5.10 (matches WhisperKit minimum) |
| Deployment target | macOS 14+ (Sonoma) |
| Products | `MurmurCore` library + `MurmurMac` executable |
| Dep | `argmaxinc/WhisperKit` exact `1.0.0` (pinned, not `from:`) |
| Sub-product chosen | `WhisperKit` only (NOT `ArgmaxOSS` umbrella) |
| CI runner | `macos-14` (matches old murmur-voice convention to dodge macos-latest churn) |

## OPEN_QUESTIONS carried forward

1. **CI first-run verification**: workflow queued at commit time; if it fails, Sprint 2.1 follow-up.
2. **Xcode project (.xcodeproj)** — Sprint 2 used pure SPM. For TestFlight / code signing / entitlements in Sprint 3+ we'll need an Xcode project (XcodeGen or manual).
3. **iOS target** — not added in Sprint 2 per BRIEF v0.1 scope. Sprint 3+/v0.2 work.
4. **WhisperKit model size default** (tiny/base/small) — needed before first actual transcription sprint.
5. **App Store BYOK policy check** — deferred from Sprint 1, becomes blocking before any iOS submission.
6. **License decision** — placeholder in repo, real choice before external user invite.
7. **Self-recorded fixture set** — Sprint 3 task per BRIEF quality gate.

## Next sprint (recommended)

```
/sprint murmur-mvp-v01-audio-capture   (eng-lead)
  Goal: AVAudioEngine record → save to wav → WhisperKit transcribe to text
  Output: command + button works, English audio in → English text out
```

Or smaller first slice:

```
/sprint murmur-whisperkit-model-load    (eng-lead)
  Goal: download tiny model on first launch, instantiate WhisperKit, show
        "model ready" UI; nothing else
  Output: dogfoodable "model loaded" indicator, foundation for audio sprint
```

Recommend the latter — incremental, isolates WhisperKit model-loading risk.
