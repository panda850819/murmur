---
date: 2026-05-18
type: pitfall
status: resolved
topic: xcodebuild "BUILD SUCCEEDED" but dogfood shipped a days-stale binary
tags: [pitfall, build, xcodebuild, deriveddata, deploy, murmur, process]
sprint: murmur-sprint-5-hotkey-paste
---

# "BUILD SUCCEEDED" while the deployed app was frozen days behind

## Symptom

A whole multi-iteration debugging session on an audio bug
(no-capture-on-2nd, then `-10868`) where every "fix → rebuild → install
→ user tests → still broken / new error" cycle seemed to make things
worse or change unpredictably. Every `xcodebuild … build` reported
**BUILD SUCCEEDED**. Every fix compiled clean and passed 30/30 SwiftPM
tests. The user re-granted TCC ~6 times. None of it moved the needle —
because **not one line of the session's code was ever running**.

## Root cause (two compounding bugs)

1. **xcodebuild without `-derivedDataPath` was not refreshing the default
   DerivedData app.** `scripts/bootstrap.sh` regenerates
   `Murmur.xcodeproj` every run (XcodeGen). The default DerivedData
   `MurmurMac.app` stayed frozen at a timestamp **4 days old** while
   xcodebuild kept printing BUILD SUCCEEDED.
2. **`dogfood-install.sh` located the app with
   `find ~/Library/Developer/Xcode/DerivedData … | head -1`.** That
   `head -1` returned the *stale* DerivedData bundle. So the install step
   faithfully copied a 4-day-old binary to `/Applications` every time.

Net: the deployed `/Applications/Murmur.app` predated the entire audio
investigation. "fresh-AudioProcessor regressed #1", "pause/resume",
"-10868", "Chinese→English" were **all observed on the stale binary** —
every conclusion drawn from them is void.

## How it was finally caught

Diagnostics added in code (an on-screen `[#n, path, mic=…]` suffix) did
**not** appear in the user's screenshot. That mismatch — "the running app
lacks code I definitely committed" — was the tell. Confirming:
`stat -f %Sm` on the DerivedData app showed a 4-day-old mtime;
`strings` on `MurmurMac.debug.dylib` lacked the new string literals.

## Second layer: incremental no-ops even WITH a pinned path

Pinning `-derivedDataPath .ddp` was necessary but **not sufficient**: a
plain incremental `xcodebuild … build` after editing a local SwiftPM
package source (`Core/Sources/MurmurCore/*.swift`) still printed BUILD
SUCCEEDED while NOT recompiling the package — the `.ddp` app stayed at
the previous build. XcodeGen regenerating the project + Xcode's local
package build cache makes incremental builds unreliable. The
`find -newer` stale-build guard caught this second ghost attempt before
it shipped. **`clean build` is mandatory** for this project's
dogfood loop; `scripts/dogfood.sh` enforces the whole correct sequence.

## Fix

- Build with an explicit, in-repo derived data path AND `clean`:
  `xcodebuild … -derivedDataPath .ddp … clean build` (`.ddp` gitignored).
- One-shot `scripts/dogfood.sh` (bootstrap → clean build → install) so
  the sequence cannot be done wrong by hand.
- `dogfood-install.sh` installs from `"$REPO/.ddp/Build/Products/Debug/
  MurmurMac.app"` — a deterministic path, never a global `find`.
- **Stale-build guard**: the install script `find … -newer "$APP"` over
  `Core/Sources` + `Sources`; if any `.swift` is newer than the built
  bundle it refuses to install. Fail loud instead of shipping a ghost.
- Deploy proof: after install, `strings` the deployed dylib for a known
  current marker before declaring it testable.

## Lessons

1. **"BUILD SUCCEEDED" proves the compiler ran, not that the artifact you
   test is the artifact you built.** For any build→install→manual-test
   loop, pin the output path and assert source-not-newer-than-build.
2. When a fix "changes the symptom unpredictably" or makes a sure thing
   worse, **suspect the pipeline, not the code** — verify the running
   binary contains the change (string/symbol grep, mtime) BEFORE another
   code iteration. This would have saved the entire session.
3. A regenerated Xcode project (XcodeGen) + default DerivedData is a
   known staleness trap; always use a fixed `-derivedDataPath`.
4. Code-level instrumentation that fails to appear in the user's UI is
   itself the highest-signal diagnostic — treat "my change isn't there"
   as a pipeline alarm, not a fluke.

## Origin

- Murmur Sprint 5 dogfood, 2026-05-14 → 2026-05-18. Cost: ~an entire
  multi-turn session of audio debugging + 6 user TCC re-grants, all on a
  ghost binary. Caught when in-code diagnostics were absent from the
  user's screenshot.
