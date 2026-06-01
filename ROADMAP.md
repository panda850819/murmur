# Murmur: Roadmap

> Feature roadmap with live progress. `BRIEF.md` still wins on hard scope/kill
> conflicts, but the **frame has shifted** (Sprint 10, CEO call): endgame is
> "personal Typeless with a gbrain compounding flywheel", **iOS-first**. This
> roadmap reflects that endgame, not the original 3-month 練手 stub.
>
> Drafted 2026-06-01 after reviewing Typeless (competitor) keyboard UX.

## Locked decisions (2026-06-01)

1. **Strategy = copy-first.** Replicate Typeless's existing UX before any net-new
   feature. New ideas get parked, not built, until the copy is at parity.
2. **LLM backend = Groq** for every LLM-backed behavior (macOS enhance/cleanup,
   keyboard translate, keyboard edit). One shared `GroqClient` across M1 + M3,
   behind a thin protocol seam so a self-hosted model can swap in later. Groq-only
   now (守 BRIEF "Groq only at MVP").
3. **Privacy stance = hybrid.** Raw transcription stays on-device (WhisperKit).
   LLM-backed behaviors (enhance/translate/edit) go through Groq cloud. murmur does
   NOT claim full local-privacy as a headline; it is honest about the cloud hop.

## Legend

```
✅ done & verified      ⏳ in progress       ⏸️ paused (blocked)
🔲 not started          🔴 open risk / decision blocking downstream
```

Progress bar = 5 segments, 20% each: `▰▰▰▱▱` = 60%.

## Snapshot (2026-06-01)

```
macOS core        ▰▰▰▰▰  ~95%   record→transcribe→enhance→paste; Groq fallback + sanity filter built
iOS foundation    ▰▰▰▱▱  ~55%   arch-B skeleton build-green, UNMEASURED on device
Typeless UX        ▱▱▱▱▱   0%    edit / translate / in-keyboard mic — none started
Dictionary+brain   ▱▱▱▱▱   0%    the actual endgame differentiator — none started
History + stats    ▱▱▱▱▱   0%    none started
Distribution       ▱▱▱▱▱   0%    no DMG, no TestFlight yet
```

---

## 🔴 Blocking decision (resolve before keyboard UX work)

**Can a keyboard extension use the mic, or not?** Sprint 10 feasibility concluded
NO (Apple bans mic in all app extensions since iOS 8) → forced arch-B (host app
records, keyboard only inserts). But **Typeless visibly puts a live mic inside its
keyboard panel** ("按住不放 🎤"). Both cannot be true. Until this is settled, every
in-keyboard-record feature below is architecturally unanchored.

- If Typeless uses Full Access mic → arch-A is alive, the whole handoff dance (switch
  to app, record, switch back, tap Insert) is unnecessary, and the UX gets far better.
- If Typeless secretly wakes the host app → arch-B stands, plan the handoff UX around it.

**Action: one focused spike to settle this before committing keyboard-UX batches.**

---

## Milestone 1 — macOS core complete (finish what's half-built)

> Closes the original v0.1 honestly. These are seams already wired, just empty.

| Feature | Status | Notes |
|---|---|---|
| Record (AVAudioEngine) | ✅ | `AudioRecorder.swift` |
| On-device transcribe (WhisperKit) | ✅ | `Transcriber.swift`, tiny/small |
| Global hotkey | ✅ | `HotKey.swift` + `GlobalHotKeyMonitor.swift` |
| Paste to foreground | ✅ | `Paster.swift` |
| Traditional-script guarantee | ✅ | `ScriptNormalizer.swift` (Sprint 8) |
| WER eval harness | ⏳ | `WER.swift` + `MurmurEval` exist; Sprint 6 PAUSED, baseline not locked |
| **Groq client** (chat + whisper) | ✅ | `GroqClient.swift`, key from `GROQ_API_KEY`; real-key smoke pending |
| **Groq cloud STT fallback** | ✅ | `FallbackTranscriber.swift`, fires on on-device throw only |
| **LLM enhance / cleanup** | ✅ | wired in `DictationCoordinator` + macOS toggle; best-effort |
| **Sanity filter** (no emoji/control chars) | ✅ | `SanityFilter.swift`; rejects → keep raw transcript |

`▰▰▰▰▰` ~95% — built + unit-tested (81 green); real-key + real-audio smoke pending Panda

## Milestone 2 — iOS foundation measured & signed

> arch-B skeleton compiles; the GO/NO-GO numbers still do not exist.

| Feature | Status | Notes |
|---|---|---|
| iOS app target (record→transcribe→handoff) | ✅ | `MurmuriOS/`, build-green on sim |
| Keyboard extension (insert-only) | ✅ | `MurmurKeyboard/`, embedded .appex, build-green |
| App Group payload/receipt channel | ✅ | `MurmurShared.swift` + Darwin notification |
| On-device latency measurement | ⏸️ | needs Panda's iPhone + signing Team |
| App Group provisioning on account tier | ⏸️ | free vs paid Developer Program unknown |
| TestFlight internal build | 🔲 | hard-kill anchor 2026-08-11 |

`▰▰▰▱▱` ~55%

## Milestone 3 — Typeless-grade keyboard UX (needs 🔴 resolved first)

| Feature | Status | Notes |
|---|---|---|
| In-keyboard mic (record without leaving app) | 🔲 | gated on the mic-in-ext decision above |
| Mode toggle: 口述 / 編輯 / 翻譯 | 🔲 | three-state keyboard switcher |
| **Edit mode** (voice command rewrites selected text) | 🔲 | needs server LLM; "Add coffee to the list" → edits selection |
| **Translate mode** (speak → insert target-lang text) | 🔲 | needs server LLM; target lang picker |
| Language target picker (繁中 / EN / …) | 🔲 | onboarding + settings |
| In-keyboard keys (換行 / delete / globe) | 🔲 | basic keyboard chrome |

`▱▱▱▱▱` 0%

> ⚠️ BRIEF tension: edit + translate both need **server-side LLM**, which softens
> the on-device-privacy posture. Typeless has the same unresolved contradiction
> (claims local-private history, but translate/edit clearly hit cloud). Decide
> murmur's stance explicitly, don't inherit the contradiction.

## Milestone 4 — Dictionary + gbrain flywheel (the real endgame)

> This is the only thing that is actually differentiated vs Typeless. Everything
> above, Typeless already has.

| Feature | Status | Notes |
|---|---|---|
| Personal dictionary (manual add) | 🔲 | BRIEF gates this — see Open questions §3 |
| Auto-add terms from usage | 🔲 | Typeless "自動添加" pattern |
| Per-context grouping (子專案: Swingvy/Yei/…) | 🔲 | Typeless dictionary sub-projects |
| **gbrain integration** (dictation ↔ brain context) | 🔲 | the compounding flywheel; murmur-only |

`▱▱▱▱▱` 0%

## Milestone 5 — History + stats

| Feature | Status | Notes |
|---|---|---|
| Dictation history (local) | 🔲 | Typeless 歷史紀錄 |
| "Audio is silent" detect + retry | 🔲 | empty-recording guard |
| Stats dashboard (time / words / WPM / saved) | 🔲 | Typeless home; low priority |

`▱▱▱▱▱` 0%

## Milestone 6 — Distribution

| Feature | Status | Notes |
|---|---|---|
| macOS signed DMG | 🔲 | |
| iOS TestFlight internal | 🔲 | gates the hard-kill criterion |

`▱▱▱▱▱` 0%

---

## Suggested batch order (for confirmation)

1. **Spike**: settle the mic-in-keyboard 🔴 (1 short investigation, unblocks M3)
2. **Milestone 1**: finish macOS core (Groq fallback + LLM enhance + sanity filter)
3. **Milestone 2**: on-device iOS measurement (needs Panda's iPhone)
4. **Milestone 3**: keyboard UX, ordered translate → edit → mode toggle
5. **Milestone 4**: dictionary + gbrain (the differentiator; do last, do properly)
6. **Milestone 5–6**: history/stats + distribution

Out of scope until explicitly pulled in: Power Mode, screen OCR, Android, multi-hotkey.
```