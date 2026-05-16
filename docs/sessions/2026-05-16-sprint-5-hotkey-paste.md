---
date: 2026-05-16
type: sprint
state: SHIPPED
topic: murmur-sprint-5-hotkey-paste — global hotkey → record→transcribe → paste into foreground app
mode: default
iteration: 2
tags: [sprint, shipped, murmur, macos, hotkey, accessibility]
---

# Sprint — Sprint 5: hotkey + paste — 2026-05-16

Completes the v0.1 macOS core dictation loop: hold a global hotkey anywhere →
record → WhisperKit transcribe → text auto-pastes into whatever app is
frontmost. Prereq SHIPPED: Sprint 3 (audio), Sprint 4 (transcribe).

## Stage progression

| Stage | Status | Output |
|---|---|---|
| 0 capability probe | ok | repo writes sprint→docs/sessions, dojo→docs/briefs (no Inbox/) |
| 1 dojo | done | `docs/briefs/2026-05-16-sprint-5-hotkey-paste-dojo.md` |
| 2 grill (lite) | done | 3 Q — sandbox fork / hotkey choice / scope OUT |
| 3 execute | done | iteration 2 (1 review loop + 2 smoke-driven fixes) |
| 4 review | done | 3×P1 + 1×P2 fixed, clean on re-review |
| 5 ship gate | SHIPPED | transport user-validated cross-app |
| 6 terminal | SHIPPED | branch `feat/hotkey-paste`, PR + this artifact |

## Key decisions (grill)

- **Drop App Sandbox for macOS.** BRIEF ships macOS as a signed DMG, not Mac
  App Store → sandbox optional. A sandboxed app cannot post synthetic ⌘V into
  another app, which is the v0.1 core loop. Entitlements emptied; `project.yml`
  drops `properties:` so XcodeGen uses the checked-in file as-is.
- **Right ⌘ hold-to-talk.** User has no `fn` key; wanted the "hold to dictate"
  model. Carbon `RegisterEventHotKey` can't bind a bare modifier nor tell
  L⌘ from R⌘ → CGEvent tap on `flagsChanged`, keycode 54. Hold-to-talk:
  press→record, release→stop+transcribe+paste; cancel on other-key chord or
  sub-180ms brush.
- **OUT of scope:** iOS path, menu-bar mode, configurable-hotkey UI, Groq
  fallback, LLM cleanup — and **transcription accuracy** (base WhisperKit
  model; user flagged it but it is a separate roadmap sprint, not this one).

## Architecture

`Pasting` protocol (test seam, Core) + `#if os(macOS)` `ClipboardPaster`
(NSPasteboard + CGEvent ⌘V, AX-gated) + un-gated `NoopPaster` so
`makeDefault()` compiles for the future iOS target. `DictationCoordinator`
gains injected `paster`, pastes on the success path, and a `cancel()` edge.
`GlobalHotKeyMonitor` (CGEvent tap) lives in the app target, not Core — it is
an input source (peer of the Button), not part of the tested flow.
`HotKeyBridge` serialises press/release into the coordinator.

## Findings (review Stage 4)

3×P1 + 1×P2, all fixed iteration 2: (1) tap never re-enabled after
`kCGEventTapDisabledByUserInput` → silent hotkey death; (2)
`Unmanaged.passUnretained(self)` → dangling-pointer risk, switched to
passRetained + balanced release; (3) `makeDefault()` hard-ref to
macOS-only `ClipboardPaster` would break the future iOS target → `NoopPaster`;
(4) AX prompt fired every paste → `prompt:false`, app-level UI drives the
grant. Re-review clean.

## Smoke loop (Stage 5, 3 iterations — the real story)

The hotkey+paste path can't be CI-tested (needs TCC grants + real keyboard +
another app frontmost), so it went through 3 user smokes:

1. **No permission UI shown at all.** Root cause: `accessibilityGranted` was
   sourced from `monitor.start()` (tapCreate bool), which succeeds without
   any permission. Fix: gate on `AXIsProcessTrusted()`, prompt once at launch.
2. **AX correct now, but hotkey still frontmost-only.** Root cause: a global
   keyboard tap needs **Input Monitoring** (`kTCCServiceListenEvent`), a
   *different* TCC permission from Accessibility. Fix: `IOHIDCheckAccess`
   detection + `IOHIDRequestAccess` prompt, tracked as a separate state, with
   a two-item permission checklist in the UI.
3. **PASS.** User: cross-app hotkey + auto-paste both happen automatically.

Pitfall captured:
`docs/learnings/pitfalls/2026-05-16-macos-input-monitoring-vs-accessibility-cgevent-tap.md`

## Verification

`cd Core && swift build` ✓ · `swift test` **24/24** ✓ (6 new: 4 paste-path +
2 cancel) · `./scripts/bootstrap.sh` ✓ · `xcodebuild … build` **BUILD
SUCCEEDED** ✓ · Functional: user smoke iter 3 PASS (cross-app hotkey → speak
→ text auto-pastes at cursor).

## Terminal state: SHIPPED

Transport (the Sprint 5 deliverable) user-validated. Branch
`feat/hotkey-paste`. Only-known limitation is out-of-scope by design.

## OPEN_QUESTIONS

1. **Transcription accuracy (base model).** "測試內容" → "So, it's the name
   wrong."; trailing " Thank you." = classic Whisper short-clip silence
   hallucination. Out of S5 scope. Strongest signal for the next sprint:
   model-size bump / Groq fallback / LLM cleanup (all already on ROADMAP).
2. **Ad-hoc cdhash churn.** Every `xcodebuild` invalidates the TCC grants.
   Dogfood from a stable copied `/Applications/Murmur.app`; the real fix is
   Developer ID signing — belongs to the signed-DMG release sprint.
3. **Clipboard clobber.** Transcript left on the general pasteboard (no
   restore). Accepted v0.1; documented in `Paster.swift`.
4. **Right⌘ keycode 54** is layout/keyboard dependent. Fine for the user's
   Apple keyboard; revisit only if dogfood surfaces it.

## Origin

- Intake: `/sprint murmur-sprint-5-hotkey-paste` (next step after S4 SHIPPED)
- Dojo: `docs/briefs/2026-05-16-sprint-5-hotkey-paste-dojo.md`
- Prereqs SHIPPED: `docs/sessions/2026-05-15-sprint-4-transcribe.md`
- Persona: `pandastack:eng-lead`
