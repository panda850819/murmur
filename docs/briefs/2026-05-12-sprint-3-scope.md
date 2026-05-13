---
date: 2026-05-12
type: brief
source: office-hours
topic: sprint-3-scope
tags: [brief, office-hours, sprint-3, scope]
---

# Sprint 3 scope decision

## Problem

Sprint 2 (5/11) 結尾 eng-lead artifact 推薦 Sprint 3 = `whisperkit-model-load`
（理由：incremental, isolates WhisperKit model-loading risk）。但 BRIEF quality
gate 同時把 fixture-set 列為 Sprint 3 task。三個候選擺著沒選：
model-load / audio-capture / fixture-set。

## Original premise

「Sprint 3 該開哪個 — 從 model-load / audio-capture / fixture-set 三選一。」
隱性假設：三條都是合理的、一個 /sprint session 能裝得下。

## Revised premise (after grill)

Sprint 3 真正卡的點不是 WhisperKit model-load（Sprint 2 已驗 symbol 可達、
CI 跑得起來），是 **AVAudioEngine** — Panda 沒寫過 Swift audio code，
argmaxinc demo 的 audio path 也還沒讀。

「audio-capture 端到端」的完整工作（讀 demo + Xcode-ify + AVAudioEngine
record + WhisperKit transcribe + SwiftUI button + 顯示）估 4-7 hr，**不可能
塞進一個 1-2 hr 的 /sprint session**。必須拆。

額外被勾出的限制：macOS mic permission 要 `NSMicrophoneUsageDescription` +
`.app` bundle，純 SPM `swift run` 拿不到正確的 permission dialog。OPEN_Q #2
（Xcode project 何時引入）原本標 v0.2 才卡，**實際 v0.1 macOS Sprint 3 就會撞到**。
解法選 P3：現在就引入 Xcode project / XcodeGen。

## Dojo finding (2026-05-12) — risk significantly reduced

讀過 `argmaxinc/WhisperKit` 1.0.0 source 後重要發現：

**WhisperKit 自帶 `AudioProcessor` 類別**，內含完整 cross-platform AVAudioEngine
setup。我們**不必從零寫 AVAudioEngine**。Public API：

```swift
// 請求 mic 權限（cross-platform）
guard await AudioProcessor.requestRecordPermission() else { return }

// 列可用 input device
let devices = AudioProcessor.getAudioDevices()

// 開錄音（內部 setupEngine 已處理 16kHz mono Float32 PCM + iOS/macOS 差異）
try audioProcessor.startRecordingLive(inputDeviceID: id) { samples in
    // [Float] PCM buffer 16kHz mono, 100-400ms chunks
}

// 收尾
audioProcessor.stopRecording()

// 把錄到的 samples 寫成 wav 或 load 既有 wav
try AudioProcessor.loadAudioAsFloatArray(fromPath: path)
```

`AudioProcessor.swift` 內 `setupEngine()` (line 974) 已用 `#if os(macOS)`
處理 AVAudioSession 不存在 macOS 的差異。Sprint 3 之前以為要動手摸的東西，
WhisperKit 已經包好。

**Sprint 3 工作量重估**：

| 任務 | 原估 | 新估（用 AudioProcessor） |
|---|---|---|
| 讀 demo audio path | 30-60 min | 已完成（dojo 階段） |
| Xcode-ify (XcodeGen) | 60-120 min | 60-120 min（不變） |
| AVAudioEngine setup | 60-120 min | **0 min**（WhisperKit 已包） |
| Wire AudioProcessor + permission + button | — | 45-60 min |
| 存 [Float] samples 成 wav | 30 min | 30-45 min |
| SwiftUI Record/Stop button + state | 30-60 min | 30-60 min |
| **Total** | **4-7 hr** | **2.5-4.5 hr** |

兩 sprint 拆法仍然合理（Sprint 3 = capture + save wav，Sprint 4 = transcribe
+ UI 顯示），但 Sprint 3 完成機率大幅上升，估時可能落在 2-3 hr。

**WhisperAX 參考點**（`Examples/WhisperAX/`）：
- 純 SwiftUI（無 AppKit），跨 iOS / macOS / watchOS 同 codebase
- entitlements: `app-sandbox` + `device.audio-input` + `network.client` +
  `files.user-selected.read-write`（已對齊 Sprint 3 `project.yml`）
- mic permission string 用 build setting `INFOPLIST_KEY_NSMicrophoneUsageDescription`
  而非寫 Info.plist（modern Xcode 15+ 慣例；XcodeGen `info:` block 走同路徑）

## Alternatives considered

- A: Xcode-ify only — Sprint 3 只做 .xcodeproj + Info.plist + scaffold 跑起來，
  不動 audio。 — **Reject**（Sprint 3 沒進 audio，產出空，動力不夠）
- B: 整包一次到位 — 一個 sprint 把 Xcode + audio + transcribe + UI 全 ship。
  — **Reject**（3-5 hr+ 工作量，違反 /sprint 1-2 hr 哲學，三未知同時打開
  難 isolate debug，直接踩 BRIEF failure mode #1 防禦）
- C: 兩半拆 — Sprint 3 = Xcode + AVAudioEngine record → wav；
  Sprint 4 = wav → WhisperKit transcribe → SwiftUI 顯示。 — **Add (chosen)**

## Chosen approach

**C** — 兩半拆。Sprint 3 = Xcode-ify + 錄音存 wav；Sprint 4 = transcribe + UI。
每個 sprint 都有可感知產出（先聽到自己錄的 wav，後看到 transcription），
未知隔離，符合 BRIEF "incremental, isolates risk" + /sprint 1-2 hr 哲學。

## Scope

**In (Sprint 3)**：
- Dojo phase：讀 argmaxinc/WhisperKit `Examples/` 看 macOS / iOS demo 有沒有
  AVAudioEngine 範例、API 細節
- 引入 Xcode project（XcodeGen `project.yml` 或手寫 `.xcodeproj`）
- `Info.plist` with `NSMicrophoneUsageDescription`
- 最小 entitlements + dev signing（不 TestFlight，本機跑就好）
- AVAudioEngine 開 mic → 錄 N 秒 → 存成 wav（到 `/tmp/` 或 `~/Library/`）
- 用 QuickTime 開 wav 能聽到 → done 線
- SwiftUI 一個「Record / Stop」button（state binding 就好，不用美化）
- README 更新 build flow（從 `swift run` 改成 Xcode / `xcodebuild`）

**Out (Sprint 3，明確不做)**：
- WhisperKit transcribe（Sprint 4）
- 顯示 transcription 文字（Sprint 4）
- LLM enhance（v0.1 後段）
- hotkey + 背景錄 + paste（v0.1 完整 spec，Sprint 5+）
- fixture-set 自錄 + WER baseline（pushed to Sprint 5+ — BRIEF quality gate
  的位置改成 release 前必達，不再強制 Sprint 3）
- iOS target（v0.2）
- 第二個 SwiftUI 頁面 / 設定 UI

**Pre-Sprint 3 gate (dojo 必過)** — ✅ 已於 2026-05-12 完成：
- ~~確認 argmaxinc/WhisperKit `Examples/` 有 macOS demo~~ → 有 `WhisperAX/`，
  純 SwiftUI 跨 iOS / macOS / watchOS。AVAudioEngine 細節 WhisperKit 內建
  `AudioProcessor` 已處理，跨平台 `#if os(macOS)` 完整。
- ~~確認 XcodeGen 對 Swift Package + executable target 結構支援良好~~ →
  XcodeGen 2.45.4 已 `brew install`；`packages:` 引用 root `Package.swift`，
  MurmurCore 留 SPM，Xcode project 只包 MurmurMac.app。範本見 `project.yml`。

## Sprint 3 goal lock (L0-L3)

### L0 — Done line goal（ship gate 量化條件）

```
goal-L0-a  錄音長度 ≥ 3s（避免 race condition / 太短不確定錄到沒）
goal-L0-b  wav format = 16kHz mono Float32 PCM
           （WhisperKit native input，Sprint 4 不必再 resample）
goal-L0-c  存到 ~/Library/Application Support/Murmur/Recordings/<timestamp>.wav
           （sandboxed app 預設讀寫位置，符合 entitlements）
goal-L0-d  錄音 hard cap 30s（防無限錄音）
goal-L0-e  能用 QuickTime / Finder Preview 開 wav 並聽見內容
goal-L0-f  Mic permission dialog 顯示 "Murmur" 而非 "Terminal"
```

Sprint 3 SHIPPED 定義 = 全部 L0-a ~ L0-f 同時滿足。

### L1 — Time-box / 中止規則

```
goal-L1-a  /sprint nominal: 1-2 hr
           Sprint 3 估時（dojo 後修正）: 2-3 hr
           → [2 hr] 自我 checkpoint，問「卡哪？」
           → [3 hr] hard PAUSED，寫 Inbox/sprint-*.md，不硬撐
goal-L1-b  3-strike rule (eng-lead 鐵律) — 同個 bug try 3 次沒過 → 停下換 framing
goal-L1-c  XcodeGen ≤ 30 min 沒生出 .xcodeproj → fallback 手寫最小 .xcodeproj
goal-L1-d  AudioProcessor 整合 ≤ 30 min 沒收到 buffer callback →
           暫停回頭看 WhisperAX/Views/ContentView.swift line 1564, 1590, 1610 範例
```

### L2 — 技術決策（dojo 已鎖 / sprint 內固定）

```
goal-L2-a  ✅ XcodeGen（已選，project.yml 已寫）
goal-L2-b  Bundle ID = com.panda.murmur（已寫進 project.yml；改名要動 Keychain）
goal-L2-c  Signing = ad-hoc local（CODE_SIGN_IDENTITY: "-"，dev 本機跑）
           付費 Apple Developer($99/yr) 延後到 Sprint 5+ iOS target 才買
goal-L2-d  ✅ Package.swift + Xcode project 並存
           - MurmurCore 留 Package.swift（cross-platform lib + 跑 swift test）
           - MurmurMac.app 由 Xcode project 包裝（Info.plist + entitlements + signing）
           - project.yml `packages: MurmurCore: { path: . }` 引用同一 Package
goal-L2-e  ✅ audio output format = 16kHz mono Float32 PCM
           直接走 WhisperKit.AudioProcessor 給的 buffer，不自己 resample
goal-L2-f  ✅ argmaxinc demo 已讀 — WhisperAX/ContentView.swift line 1564/1590/1610
           是 AudioProcessor 整合範例
```

### L3 — Out-of-scope hard line（防 drift）

```
[禁止]  WhisperKit transcribe                 → Sprint 4
[禁止]  顯示 transcription 文字                → Sprint 4
[禁止]  LLM enhance (Groq cleanup)            → v0.1 後段
[禁止]  hotkey / background record            → Sprint 5+
[禁止]  auto-paste 到前景 app                  → Sprint 5+
[禁止]  fixture 自錄 + WER baseline           → Sprint 5+
[禁止]  UI 美化（button 樣式 / 動畫 / 顏色）   → 永遠不在 v0.1
[禁止]  設定第二頁                            → BRIEF v0.1 禁
[禁止]  iOS target                            → v0.2
[禁止]  Multi-device input picker             → 用 system default mic 就夠
[禁止]  AudioStreamTranscriber 串流模式        → Sprint 4 才考慮
```

Drift signal: sprint 中途冒出「順手把 X 也做了」念頭 → 立刻 stop，寫進
Inbox 當下個 sprint 候選，**不准在這個 sprint 做**。

## Next skill (recommended)

```
Shape: single-target-iterative
Reasoning: Sprint 3 是單一目標（Xcode-ify + audio record to wav）的線性執行,
           不是 N 個獨立 branch 平行展開。Sprint 4 接續同一條目標線。
           Q2 of skill-decision-tree.md = No (no independence audit needed).

Recommended skill:
  → /sprint murmur-sprint-3-xcode-audio

Persona for next skill (per lib/skill-decision-tree.md routing table):
  → eng-lead
  Reason: code-heavy task — XcodeGen / Info.plist / AVAudioEngine / Swift。
           沒 UI 設計決策（button 美化在 v0.1 後段，這個 sprint 只要 state 通），
           沒跨團隊協調，沒策略 scope 重審。staff engineer 抓 minimal diff +
           root cause 最對位。
```

## Gotchas surfaced

從 Sprint 2 artifact + 本次 grill + dojo finding：

1. **WhisperKit `Package.swift` 寫的 platform minimum 跟實際 code 要的不一樣**
   — 已紀錄到 `learnings/pitfalls/whisperkit-package-platform-vs-code-mismatch.md`，
   CI 必須跑 macos-15 / Xcode 16+
2. ~~**AVAudioEngine 跨平台差異**~~ — **SUPERSEDED**: WhisperKit 內建
   `AudioProcessor.setupEngine()` 已用 `#if os(macOS)` 處理 iOS / macOS
   AVAudioSession 差異。不必自己處理。
3. **macOS mic permission for SPM exec** — `swift run` 出的 binary 沒
   .app bundle，permission dialog 跳 Terminal 名字而非 Murmur。**強迫 Sprint 3
   引入 Xcode project**（goal-L0-f）
4. **/sprint 1-2 hr 撐不住 4-7 hr 工作量** — Sprint 2 artifact "Next sprint"
   推薦 model-load / audio-capture 都單獨 ship 不完，需要拆兩半（C）。
   dojo finding 後 Sprint 3 估時下修到 2-3 hr，仍超 1-2 hr nominal，
   goal-L1-a 設 2/3 hr checkpoint。
5. **WhisperKit `recommendedModels()` API** — Sprint 4 要選 default model，
   不要寫死 `"tiny"`，呼叫 `WhisperKit.recommendedModels().default` 讓
   WhisperKit 根據 device 自己挑。Sprint 4 dojo 再讀一次 demo line 35-38。
6. **App Sandbox + ad-hoc signing 互動** — entitlements 啟用 sandbox 後，
   ad-hoc signed binary 仍可跑（dev 用），但要從 Xcode build & run，不能
   雙擊 .app（系統會擋）。Sprint 3 過程記得從 Xcode 跑，不從 Finder 開。

## Gate Log

- Stage 1 (load context): skipped (--quick mode). Context loaded mid-session
  via repo scan: BRIEF / ROADMAP / Sprint 2 artifact / Package.swift / CI yaml /
  Source 三檔 / Tests 一檔
- Stage 2 (premise challenge): 4 questions asked, 0 push-once invocations,
  escape-hatch not fired. Answers:
  - Q1 (real risk): A — AVAudioEngine, not model-load
  - Q2 (demo read?): Y — not yet
  - Q3 (Sprint 3 SHIPPED def): b — GUI button → transcription
  - Q4 (mic permission path): P3 — introduce Xcode project now
- Stage 3 (alternatives): chose C (two-half split)
- Stage 4 (premise refresh): premise partially load-bearing — direction
  unchanged, scope sizing + Sprint 3 boundary shifted significantly
- Stage 5 (output): brief saved to docs/briefs/2026-05-12-sprint-3-scope.md

## OPEN_QUESTIONS

從 Sprint 2 artifact 帶下來，dojo 後狀態更新：

1. **WhisperKit model 大小 default**（tiny/base/small）— 解法已找到：
   Sprint 4 呼叫 `WhisperKit.recommendedModels().default`（device-aware），
   不必自己挑。Sprint 4 dojo 階段 confirm。
2. **App Store BYOK policy check** — v0.2 iOS submission 前需確認；Sprint 3-4
   先不卡
3. **License decision** — 邀外人前需定；目前 placeholder ok
4. **舊 murmur-voice README "successor" 文案** — 等新 repo dogfoodable build
   後再寫
5. ~~**XcodeGen vs 手寫 .xcodeproj**~~ — **RESOLVED**: XcodeGen 2.45.4 已裝，
   `project.yml` 已寫進 repo root。Sprint 3 啟動就 `xcodegen generate`。
6. **何時付 Apple Developer $99/yr** — 延後到 Sprint 5+ 需 TestFlight 才付。
   Sprint 3-4 用 ad-hoc local signing（`CODE_SIGN_IDENTITY: "-"`）夠用。
7. **Murmur.xcodeproj 要不要 commit?** — XcodeGen 慣例：commit `project.yml`，
   gitignore `*.xcodeproj/`（現有 `.gitignore` 已含）。每人 `xcodegen generate`
   產自己的。不 commit `.xcodeproj` 才不會跟 Xcode auto-edit 衝突。
