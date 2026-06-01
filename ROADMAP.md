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
macOS 3 modes     ▰▱▱▱▱  ~20%   dictate done; translate + ask reuse M1 GroqClient (UNBLOCKED)
iOS foundation    ▰▰▰▱▱  ~55%   arch-B skeleton build-green, UNMEASURED on device
iOS keyboard UX    ▱▱▱▱▱   0%    arch settled (arch-B + session window); gated on device measurement only
Dictionary+brain   ▱▱▱▱▱   0%    the actual endgame differentiator — none started
History + stats    ▱▱▱▱▱   0%    none started
Distribution       ▱▱▱▱▱   0%    no DMG, no TestFlight yet
```

---

## ✅ Resolved (2026-06-01 mic spike `wf_ea67c577-101`, high confidence)

**Can a keyboard extension use the mic? NO — confirmed, citation-verified.** Apple
blocks mic capture from every app extension at the OS process level; Full Access
(RequestsOpenAccess) does NOT unlock it (its capability list omits mic; playback ≠
capture). On-device STT in-extension is independently dead: whisper-tiny ~125–273 MB
RSS vs a ~30–50 MB keyboard jetsam cap → guaranteed OOM-kill.

**Typeless does NOT contradict this.** Its in-keyboard mic is a UI trigger only; the
real recording runs in the Typeless **host app**. Its own App Store listing says
dictation "keep[s] listening" after the keyboard closes / across app-switches —
impossible for an extension (torn down on dismissal). So Typeless is arch-B too.

→ **arch-B confirmed** (host records → App Group → keyboard inserts), exactly the
walking skeleton on this branch. The win from the spike: copy Wispr Flow's
**pre-authorized session window** so the host-app bounce is once-per-window
(5min/15min/1hr), not once-per-dictation. Hard edge: a Darwin notification will NOT
resume a suspended/terminated host, so the host must hold an active session — the
session-window pre-auth is load-bearing, not cosmetic.

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

> **Reframed 2026-06-01** after seeing Typeless's macOS desktop app: on the
> desktop Typeless is a pure **three-mode hotkey app, no keyboard extension**.
> That is exactly murmur's macOS architecture (global hotkey + Accessibility
> paste + mic). So macOS parity is UNBLOCKED and near-term — the mic-in-keyboard
> 🔴 risk applies only to the iOS keyboard track (M3b), not here.

### M3a — macOS three modes (unblocked, reuses M1 GroqClient)

Typeless macOS hotkey map: 口述 = Right Cmd · 翻譯 = Right Shift+Right Cmd ·
詢問 = / + Right Cmd. murmur's dictate hotkey is already Right Cmd.

| Feature | Status | Notes |
|---|---|---|
| 口述 dictate + auto-cleanup | ✅ | M1: record→transcribe→enhance→paste. Typeless's "um 7am→3pm" demo = our enhance |
| **翻譯 mode** (speak → insert target-lang) | 🔲 | new hotkey chord + `GroqClient.chat` translate prompt + target-lang setting |
| **詢問 mode** (ask about selected text) | 🔲 | new hotkey + read selection via Accessibility + `GroqClient.chat` |
| Target-language setting | 🔲 | one Picker; default 英語(美國) |
| Web-search in 詢問 (stretch) | 🔲 | Typeless "Searching the web"; beyond Groq chat, defer |

`▰▱▱▱▱` ~20% (dictate+enhance done; translate/ask reuse the M1 client)

### M3b — iOS keyboard UX (arch settled; gated on device measurement only)

| Feature | Status | Notes |
|---|---|---|
| ~~In-keyboard mic~~ | ❌ | impossible by OS law — host app records (arch-B confirmed) |
| **Pre-authorized session window** (host holds mic) | 🔲 | Wispr-Flow pattern; bounce to host once per window, not per dictation |
| Host must hold active session | 🔲 | Darwin notification won't resume a suspended host — load-bearing |
| Mode toggle / translate / ask in keyboard | 🔲 | iOS port of M3a once on-device measured |
| In-keyboard keys (換行 / delete / globe) | 🔲 | basic keyboard chrome |

`▱▱▱▱▱` 0%

> ⚠️ BRIEF tension: translate + ask both need **server-side LLM**, softening the
> on-device-privacy posture. Locked decision §3 already accepts the hybrid stance
> (raw STT on-device, LLM behaviors via Groq). Typeless has the same cloud hop;
> murmur is just honest about it.

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

1. ✅ **Milestone 1**: macOS core (Groq client + enhance + STT fallback + sanity) — DONE, committed `feat/m1-macos-groq-enhance`
2. **M3a**: macOS three modes — 翻譯 then 詢問 (both reuse M1 `GroqClient.chat`). Unblocked, no iOS hardware needed. ← next
3. **Spike (M0)**: settle the mic-in-keyboard 🔴 for the iOS track
4. **Milestone 2**: on-device iOS measurement (needs Panda's iPhone)
5. **M3b**: iOS keyboard UX (port M3a once arch settled)
6. **Milestone 4**: dictionary + gbrain (the differentiator; do last, do properly)
7. **Milestone 5–6**: history/stats + distribution

Out of scope until explicitly pulled in: Power Mode, screen OCR, Android.
```