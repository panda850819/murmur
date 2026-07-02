---
schema_version: 1
date: 2026-06-12
type: sprint
state: SHIPPED
topic: M3a macOS three modes — translate + ask (Typeless hotkey-map parity)
mode: default
iteration: 2
tags: [sprint, shipped]
---

# Sprint — M3a three modes — 2026-06-12

## Capability probe

AGENTS ok · lib/persona ok · no docs/plans/ (conversational) · vault root = repo
(degraded 1, proceed) · **machine gap discovered mid-sprint: no Xcode.app (only
`Xcode.appdownload`, CLT-only) → local `swift build` works, XCTest/xcodebuild do
NOT. Verification gate moved to CI (ci.yml: swift test + xcodebuild on macos-15).**

## Stage progression

| Stage | Status | Output |
|---|---|---|
| 0 capability probe | degraded (vault root; Xcode gap found later) | proceed |
| 1 dojo | done | pitfalls loaded: ghost-binary, guard-across-layers, filter-no-looser-than-guard |
| 2 grill (lite) | done (autonomous: assumptions logged, not asked) | scope = M3a only; web-search stretch OUT; M5 separate sprint |
| 3 execute | done | iteration 2; eng-lead lens |
| 4 review | done | cold-review subagent: 3 P1 + 6 P2; P1s all fixed iter 2 |
| 5 ship gate | SHIPPED | CI green both rounds; merge + real-key smoke pending Panda |
| 6 terminal | ship ran | PR #9, commits 0e2992c + ea95efb |

## What was built

Typeless hotkey-map parity on macOS:

- 翻譯 translate: hold Right⇧ + Right⌘ (either order). transcribe → A' correct
  → `GroqClient.translate` (B' `GlossaryRelevanceFilter` narrows the glossary,
  same as enhance) → sanity filter → paste. Failure degrades to pasting the raw
  transcript with an error note.
- 詢問 ask: tap `/` while holding Right⌘. AX-selected text (8k cap) rides as
  reference in the user message. Failure pastes nothing (an answer didn't
  happen; the question is not a substitute).
- Target-language Picker (`@AppStorage`, default English (US)).
- New seams mirroring existing ones: `DictationMode`, `LLMChatting`,
  `SelectionReading`. Mode resolves at hotkey release → `HotKeyBridge` →
  `DictationCoordinator.toggle(mode:)`.
- CGEvent tap `.listenOnly` → `.defaultTap` so the `/` chord is swallowed
  (would otherwise hit the focused app as ⌘/ = toggle-comment).

## Findings (review Stage 4, cold subagent)

Fixed in iteration 2 (commit ea95efb):

- **P1** `holdActive` tap-state mirror could wedge `true` on a missed Right⌘
  keyUp (secure input / lock screen / tap disable) → every `/` system-wide
  swallowed forever. Fix: verdict reads Right⌘ off the slash keyDown's own
  flags; only keyDown/keyUp pairing state remains; `stop()` resets it.
- **P1** Active tap on the main run loop = a Murmur main-thread hitch becomes
  system-wide typing latency (`.defaultTap` is synchronous). Fix: dedicated
  `userInteractive` tap thread with its own run loop.
- **P1** Permission attribution: an ACTIVE keyboard tap is gated on
  Accessibility, not Input Monitoring; failed `start()` now points the UI at
  the AX row. Stale listen-only comments updated.
- **P2** paste-failure no longer clobbers a translate-degrade error note.

## Gate Log

- Stage 2 autonomous: assumptions in lieu of questions (logged below).
- Stage 4 iter 1 → [approve] (self), findings fed back, iter 2 → clean → ship.

## Terminal state: SHIPPED

PR #9 (`feat/m3a-three-modes`), CI green twice (swift test 95 tests incl. 14
new; xcodebuild app build). Merge + real-key/real-audio smoke pending Panda.

## OPEN_QUESTIONS

- Ask-mode paste REPLACES the selection it answered about (synthetic ⌘V over a
  live selection). Typeless's actual semantic unverified — if it preserves the
  source, this needs a caret-move or append strategy.
- `/` is keycode 44 = physical ANSI slash; wrong key on AZERTY/QWERTZ/JIS.
  Fine for single-user dogfood.
- `/` tapped during a sub-180ms (minHold) hold is swallowed AND the dictation
  cancels — user loses both. Accepted loss.
- Chord-resolution reducer in `GlobalHotKeyMonitor.process()` is pure but
  lives in the untestable app target; could move into MurmurCore for unit
  coverage. Deferred.
- Local toolchain: finish the Xcode.app install to restore local XCTest.

## Process note

Panda directive (this session, saved to runtime memory
`fable-architect-not-implementer`): main session = architect (spec / review /
integrate), implementation → subagents. M3a was written main-session before
the directive landed; M5 (history + silent-detect + stats) dispatched to an
implementation subagent on stacked branch `feat/m5-history-stats` mid-session.
