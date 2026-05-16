---
date: 2026-05-16
type: prep
flow: sprint
topic: murmur-sprint-5-hotkey-paste — global hotkey → record→transcribe → paste into foreground app
tags: [prep, dojo]
---

# Dojo prep — Sprint 5: hotkey + paste

## Capability probe

All green. `[2]` repo has no `Inbox/` (S3 renamed it away) → sprint artifact
goes to `docs/sessions/`, dojo to `docs/briefs/` (established repo pattern).

## Past cases

- `docs/sessions/2026-05-15-sprint-4-transcribe.md` — S4 SHIPPED: WhisperKit
  on-device transcribe, Chinese end-to-end validated. `DictationCoordinator`
  explicitly names this sprint: *"the seam where the BRIEF's later
  Groq-fallback and paste-to-foreground steps will attach."*
- `docs/sessions/2026-05-14-sprint-3-audio.md` — AVAudioEngine WAV recorder,
  `AudioRecorder` idempotency pattern (re-used by coordinator).
- `docs/learnings/pitfalls/2026-05-14-xcodegen-local-package-...` — must run
  `./scripts/bootstrap.sh` after any `project.yml` edit; `xcodebuild` must NOT
  pass `-arch arm64` (use `ONLY_ACTIVE_ARCH=YES`, destination `platform=macOS`).

## Lib loaded

- ✓ lib/capability-probe.md (substrate availability)
- ✓ lib/skill-decision-tree.md (persona routing → eng-lead)
- ✓ lib/gate-contract.md (Stage 4 4-option gate)
- ✓ lib/push-once.md / escape-hatch.md (grill discipline)

## Gotchas (prior sessions + Apple-stack reality)

1. **[ARCHITECTURAL FORK] App Sandbox blocks auto-paste-into-other-apps.**
   Current `Murmur.entitlements` has `com.apple.security.app-sandbox: true`.
   Global hotkey via Carbon `RegisterEventHotKey` works sandboxed. But
   *posting a synthetic ⌘V (CGEvent) into another app* requires Accessibility
   trust (`AXIsProcessTrusted`), which a sandboxed app effectively cannot
   obtain for controlling *other* processes. **BRIEF says macOS ships as a
   signed DMG, NOT Mac App Store** → sandbox is optional. Dropping the sandbox
   on the macOS target is the pragmatic dogfood path to real auto-paste.
   This is the #1 grill question.

2. **xcodegen regen discipline.** Any `project.yml` / entitlements / Info.plist
   change → `./scripts/bootstrap.sh` before `xcodebuild`. Don't hand-edit the
   gitignored `.xcodeproj`. Verify with the exact invocation in bootstrap.sh
   output (no `-arch arm64`).

3. **Coordinator is the attach seam.** `DictationCoordinator.toggle()` ends
   with `transcript = ...; phase = .idle`. Paste hooks in right there. Hotkey
   drives `toggle()`. Keep the `Recording`/`Transcribing` test-seam pattern —
   add a `Pasting` protocol so the flow stays unit-testable without a real
   pasteboard / event tap. SWIFT_STRICT_CONCURRENCY: minimal, Swift 5.10,
   `@MainActor` on coordinator.

## Suggested entry point

Resolve the sandbox fork first (grill Q1). If "drop sandbox for macOS":
add `MurmurCore` `Pasting` protocol + `ClipboardPaster` (NSPasteboard + CGEvent
⌘V, AX-gated), a Carbon `GlobalHotKey` wrapper, wire both through
`DictationCoordinator`, update `project.yml` (sandbox off, add
`NSAppleEventsUsageDescription`/AX prompt copy), `./scripts/bootstrap.sh`,
build, manual smoke (hotkey from another app → speak → text lands at cursor).
