# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Murmur: voice → text dictation for macOS (+ future iOS). **Personal dogfood tool, not a product** — `BRIEF.md` is the binding scope cap and wins on any scope/kill conflict; `ROADMAP.md` is the feature wishlist (frame has shifted to "personal Typeless with a gbrain flywheel, iOS-first"). Hard kill date `2026-08-11`. No differentiation claim; never write "differentiated"/"moat"/"unique" in any artifact.

## Build, test, run

Two build systems. The shared logic is a SwiftPM package; the macOS `.app` is an Xcode project generated from `project.yml`.

```bash
# Core library + tests (this is what CI gates and what most edits touch)
cd Core && swift build
cd Core && swift test
swift test --filter MurmurCoreTests.DictationCoordinatorTests   # single test class

# macOS .app — Murmur.xcodeproj is GITIGNORED, regenerate it first
./scripts/bootstrap.sh         # xcodegen generate + patch + bake gbrain terms (idempotent)
./scripts/dogfood.sh           # clean build + stable re-sign + install to /Applications

# WER/CER regression gate (BRIEF Quality gate #1) — needs recorded fixtures
./scripts/eval.sh --bootstrap-baseline   # first time / after intentional model change
./scripts/eval.sh                        # release: fail if WER regressed
```

Requires Xcode 16+ / Swift 6 host (CI uses `macos-15`). WhisperKit v1.0.0 is pinned `exact("1.0.0")` and declared in BOTH `Core/Package.swift` and `project.yml` — versions must match exactly (the Xcode build graph doesn't propagate the transitive SPM dep through a local-package product dependency).

### Build gotchas that have cost real days (see `docs/learnings/pitfalls/`)

- **Always use `clean build` with `-derivedDataPath .ddp`** for the macOS app. Plain incremental `build` silently no-ops on `Core/` edits and Xcode's default DerivedData can freeze days behind while reporting BUILD SUCCEEDED — shipping a stale ghost binary. `dogfood-install.sh` enforces both (pinned `.ddp` path + a stale-source guard that refuses to install if any `*.swift` is newer than the built app).
- **Rerun `./scripts/bootstrap.sh`** after editing `project.yml` or whenever `Murmur.xcodeproj/` is missing. `scripts/patch-xcodeproj.py` fixes the XcodeGen 2.45.4 local-package linkage bug; xcodegen is pinned to 2.45.4 in CI for this reason — bump deliberately.
- **Dogfood signing is intentional**: `dogfood-install.sh` re-signs with a stable "Developer ID Application" identity so macOS TCC grants (Microphone / Accessibility / Input Monitoring) survive rebuilds. CI stays adhoc (no local cert). Grant the three permissions once after first install.

## Architecture

`MurmurCore` (in `Core/`) holds all testable logic, UI-free, behind protocol seams so tests inject fakes (no real mic, no ~140 MB model download, no network). The macOS app (`Sources/MurmurMac/`) is thin SwiftUI + global-hotkey glue over it.

**The dictation flow lives in `DictationCoordinator.toggle()`** — the single orchestration unit. Read it first; it wires every stage:

```
hotkey → AudioRecorder (AVAudioEngine) → WAV
       → Transcriber → WhisperKitTranscriber (on-device, actor, lazy single load)
                        └─ FallbackTranscriber → GroqClient (cloud Whisper, fires on on-device throw only)
       → TranscriptGuard.isNonSpeech  (drop "[BLANK_AUDIO]"/"(silence)" before spending a Groq call)
       → A' ProperNounCorrector.correct  (deterministic, on-device)
       → B' GroqClient.enhance  (LLM cleanup, best-effort; glossary narrowed by GlossaryRelevanceFilter)
       → A' ProperNounCorrector.correct  AGAIN  (Groq can re-mangle a corrected name; A' gets the last word)
       → SanityFilter.isClean  (reject emoji/control chars → keep raw)
       → Paster (ClipboardPaster, Accessibility ⌘V to foreground app)
```

Key invariants encoded in that flow (do not regress):

- **Enhance never blocks paste.** Groq off / no key / throws / empty / fails sanity → return the raw (A'-corrected) transcript. Cloud is opt-in purely via `GROQ_API_KEY` in the environment; absent key = pure on-device, no network.
- **A' runs twice, around the enhance hop**, and the `corrector` is captured once per dictation so both A' passes and B's glossary draw from the same instance even if the public `corrector` var is reassigned mid-flight.
- **Non-speech guard is conservative by design**: fires only when the WHOLE transcript is non-speech (bracket-depth scan). Dropping real speech is the worse failure, so a marker next to real words keeps the words.

### The proper-noun correction stack (A' / B' / C)

This is the part that needs reading multiple files to understand:

- **A' = `ProperNounCorrector`** — deterministic on-device token correction: direct-map → canonical-casing → fuzzy (Damerau-Levenshtein, length-scaled threshold). Only whole ASCII-Latin word tokens touched; CJK/punct/digits pass through. Over-correction bounded by a real-word guard (`SystemDictionary.isRealWord` via `NSSpellChecker`, main-thread AppKit — that's why the coordinator is `@MainActor`), min token length, and edit-distance threshold.
- **B' = LLM glossary** — the same term universe (`ProperNounCorrector.glossary`) is injected into the Groq enhance prompt, but **narrowed by `GlossaryRelevanceFilter` to only terms fuzzy-near the actual utterance** before going over the wire (privacy: a no-proper-noun utterance ships an empty glossary). B' has no deterministic real-word guard — the post-enhance A' pass is the hard correction guarantee.
- **C = `CorrectionStore`** — runtime-grown user corrections.
- **Term source = gbrain.** `scripts/export-gbrain-terms.sh` exports Panda's gbrain company/project entities (people opt-in via `MURMUR_TERMS_INCLUDE_PEOPLE=1`) to `terms.json`. **A+B hybrid sync**: build-time bake into the app bundle (wired into `bootstrap.sh`) + an optional runtime file in Application Support (e.g. a launchd job) that overrides the bake without rebuilding. `TermSource`/`CompositeTermSource` union them (fresher source first). Both halves are CI-safe: no `gbrain` on PATH → keep the committed snapshot, never ship empty.

`ScriptNormalizer` guarantees Traditional Chinese output; `DecodingOptions(detectLanguage: true)` is load-bearing (WhisperKit's default would translate non-English speech to English).

## Conventions

- **Ticket-gated flow**: never commit code on `main`. Work happens on an issue-keyed branch (`feat/...`, `fix/...`); the PR is the only path to `main` (public repo → GitHub Issues are the interface). Conventional Commits, no `Co-Authored-By`, no `--no-verify`.
- **Every non-trivial design decision and every build/correctness pitfall is documented** in `docs/sessions/` (sprint artifacts), `docs/briefs/` (planning), and `docs/learnings/pitfalls/`. Before changing a behavior that looks deliberately odd, grep those — the asymmetries (A' vs B' real-word guard, conservative non-speech guard, the build/signing dance) are recorded as accepted decisions, not accidents.
- **Privacy gates are pre-distribution blockers** (`ROADMAP.md` M6): `terms.json` at-rest in the bundle/git history, and B' glossary over-the-wire scoping. Don't broaden cloud disclosure without checking those.
