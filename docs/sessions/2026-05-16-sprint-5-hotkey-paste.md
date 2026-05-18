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

## Post-ship dogfood (2026-05-16, same day)

Two bugs surfaced once hold-to-talk made repeated real dictation the norm:

- **Bug #2 + all audio findings → VOID (tested a ghost binary).** The
  real bug was the build/deploy pipeline: `xcodebuild` without an explicit
  `-derivedDataPath` left the default DerivedData app frozen 4 days stale
  while reporting BUILD SUCCEEDED, and `dogfood-install.sh`'s
  `find … | head -1` shipped that stale bundle every cycle. So
  fresh-AudioProcessor-regression, the `[diag #3,2520ms,0]` "confirmed
  mechanism", pause/resume, `-10868` — **all observed on a binary that
  predated this session; every conclusion is invalid.** Caught when
  in-code diagnostics were absent from the user's screenshot. Pipeline
  fixed: pinned `-derivedDataPath .ddp`, deterministic install path,
  stale-build guard, deploy-proof. The session's audio code (pause/resume
  etc.) is NOW genuinely deployed + Developer-ID-signed for the first
  time — audio status is **UNKNOWN, to be re-baselined** on the verified
  build. Pitfall:
  `docs/learnings/pitfalls/2026-05-18-xcodebuild-stale-deriveddata-shipped-ghost-binary.md`.
- **First real audio data point + escalation deployed.** On the verified
  build, pause/resume actually ran: `[#6, resume, mic=authorized] -10868`
  — i.e. it works for sessions #1–#5 then `resumeRecordingLive()` fails
  (mic auth ruled out; H2 confirmed). WhisperKit's `AudioProcessor`
  engine lifecycle degrades under repeated use no matter how it's driven.
  Per the pre-committed escalation (not a 4th patch): `AudioRecorder`
  rewritten to own a **single persistent `AVAudioEngine`** (tap installed
  once, never reset/re-created; a capture flag gates accumulation;
  WhisperKit kept for transcription only). Pinned `clean build` is now
  mandatory (incremental no-ops even with `-derivedDataPath`; the
  stale-build guard caught a 2nd ghost). One-shot: `scripts/dogfood.sh`.
  Verified deployed (deploy-proof: rewrite string literals present in the
  Developer-ID-signed `/Applications` dylib). Awaiting first real
  multi-dictation test of the own-engine recorder.
- **Cross-model review gap closed + 2 codex findings fixed.** `/review`'s
  Step 6.5 had silently never run (it shelled a `codex-companion.mjs` that
  was never installed). Ran the `codex` CLI directly; it caught two real
  P1s, both fixed: (P1-b) `GlobalHotKeyMonitor` used aggregate
  `.maskCommand` to detect right-⌘ release → with left-⌘ also held,
  `active` never cleared and recording stuck; now uses
  `NX_DEVICERCMDKEYMASK` (0x10) side-specific flag. (P1-a) the
  `audioProcessor.audioSamples.removeAll()` before resume was still a
  main-vs-tap-thread race on WhisperKit's unsynchronised array; removed —
  we read only our own lock-guarded buffer. The pandastack `/review`
  skill itself was fixed to invoke `codex exec` directly with an honest
  availability probe.
- **Bug #1 — "Chinese comes out English" → routed to Sprint 6.** Sharpened
  root cause: `DecodingOptions(detectLanguage: true)` is unreliable on
  short dictation clips → misdetects `en`. This is a language-policy
  product decision (zh-only / configurable / model upgrade), deliberately
  NOT patched onto the S5 hotkey+paste PR. User reflected on it twice —
  per BRIEF (dogfood pain drives the roadmap) it is the next sprint.

## OPEN_QUESTIONS

1. **Sprint 6 = transcription language/quality.** `detectLanguage: true`
   misdetects on short clips → Chinese transcribed as English; base model
   accuracy weak; trailing " Thank you." = Whisper short-clip silence
   hallucination. Scope candidates (user decides at intake): configurable
   language (default zh), model-size bump, Groq fallback, LLM cleanup.
   Decision this session: defer entirely, do it properly as its own sprint.
2. **Ad-hoc cdhash churn.** Every `xcodebuild` invalidates the TCC grants.
   Dogfood from a stable copied `/Applications/Murmur.app`; the real fix is
   Developer ID signing — belongs to the signed-DMG release sprint.
3. **Clipboard clobber.** Transcript left on the general pasteboard (no
   restore). Accepted v0.1; documented in `Paster.swift`.
4. **Right⌘ keycode 54** is layout/keyboard dependent. Fine for the user's
   Apple keyboard; revisit only if dogfood surfaces it.
5. **WhisperKit `audioSamples` grows for the app session.** Since we never
   call `stopRecording()`/`startRecordingLive()` per session (pause/resume
   instead) and stopped clearing its array (codex P1-a race), WhisperKit's
   internal buffer accumulates each session's audio (only during active
   recording — paused between). ~64 KB/s of speech; fine for short-clip
   dogfood with frequent app restarts. Real resolution = the
   bypass-WhisperKit-`AudioProcessor` path (hand-rolled `AVAudioEngine`),
   which also subsumes the Bug #2 escalation.

## PR #2 review follow-up (post-SHIP, same branch)

`/review pr` ran a fresh 3-pass + cold review on the full committed diff —
including the two smoke-driven fixes (AX-detection, Input Monitoring) that
were added *after* the Stage 4 review and so had never been audited. No
functional blocker; 4 quality items, all fixed in the follow-up commit:

1. `HotKeyBridge` extracted to `MurmurCore` behind `HotKeyMonitoring` +
   `PermissionProbe` seams (it had grown real logic — 2 permission states,
   retry orchestration, task serialisation — untestable welded to the
   CGEvent tap in `@main`). +6 unit tests now cover press/release ordering,
   cancel, and the permission gating. **30/30 green.**
2. AX-trust check de-duplicated into one owner (`RealPermissionProbe`);
   `ClipboardPaster` delegates instead of reimplementing the dance.
3. `portForReenable` `nonisolated(unsafe)` → `OSAllocatedUnfairLock` —
   the cross-thread race is now synchronised, not silenced.
4. Doc comment on `reenable()` (re-enabling a tap from its own callback is
   the established pattern; Apple docs are silent, not prohibitive).

Deferred → still OPEN_QUESTIONS: `NoopPaster` honest-seam (decide at the
iOS sprint — `case unsupported` or a `precondition`); synthetic-⌘V zero
delay (add ~50ms only if dogfood surfaces Electron-app flakiness);
`inputMonitoringGranted` folding tap-create failure into the permission
hint (rare edge). Agents' "unbounded task chain" re-flag answered in-code:
bounded for the hold-to-talk shape (modifier flagsChanged doesn't
key-repeat); rationale now a code comment so it isn't re-raised.

## Origin

- Intake: `/sprint murmur-sprint-5-hotkey-paste` (next step after S4 SHIPPED)
- Dojo: `docs/briefs/2026-05-16-sprint-5-hotkey-paste-dojo.md`
- Prereqs SHIPPED: `docs/sessions/2026-05-15-sprint-4-transcribe.md`
- Persona: `pandastack:eng-lead`
