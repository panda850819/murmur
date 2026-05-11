# Murmur: Roadmap

> Long-term wishlist. `BRIEF.md` wins on every conflict.
>
> Status: stub. Real roadmap is drafted after MVP v0.1 macOS ships
> (`/sprint murmur-mvp-v01` will produce it).

## v0.1 — macOS MVP (current scope, per BRIEF)

- press hotkey → record (AVAudioEngine) → WhisperKit on-device transcribe → paste foreground app
- Groq cloud fallback when local model unavailable or offline
- Groq LLM cleanup (optional, default on)
- Self-recorded fixture set (10-20 clips) + WER baseline

**Done = Panda uses it for 7 consecutive days without falling back to murmur-voice (Tauri).**

## v0.2 — iOS native target

- Separate iOS SwiftUI target sharing `MurmurCore`
- AVAudioEngine path validated on iOS
- TestFlight internal distribution
- Hard kill anchor lives here: 2026-08-11 must hit "dogfoodable iOS TestFlight build" or kill

## v0.3+ — TBD post-v0.2

Not enumerated. The point of leaving this blank is that the BRIEF philosophy
forbids opening v0.3 work before v0.2 ships, and v0.3 ideas worth keeping
should arrive through dogfood pain, not roadmap speculation.

Candidate ideas parked (not committed):

- Glossary engine (3-condition gate before starting; see `BRIEF.md` § Open questions)
- Power Mode (per-app profiles) — VoiceInk pattern, not differentiation
- Apple Foundation Models for on-device LLM enhance
- Menu-bar UX (openquack pattern)
