---
date: 2026-06-01
type: brief
source: office-hours
topic: murmur dictation correctness — gbrain-sourced proper-noun correction
tags: [brief, office-hours, murmur, dictation, gbrain, dictionary]
---

# Murmur dictation correctness — gbrain-sourced proper-noun correction

## Problem

Panda dictates Chinese-English code-mixed developer speech (AI / blockchain
context) dense with **private proper nouns** — gbrain, Yei, Sommet, Bob,
Murmur, Abyss, Hermes. These names are out-of-vocabulary for Whisper, so the
model emits the nearest real word instead ("gbrain" → "gbrand"). His speech is
not fluent, which adds segmentation/punctuation errors on top. Generic ASR
cannot fix this: the correct spelling does not exist in the model's training
corpus, so it has to be injected from the user's own context. The errors are
pervasive and systematic, not one-off.

## Original premise

Fix ASR accuracy on code-mix + domain jargon via a dictionary; build the M3a
copy-Typeless modes (translate, ask). Translate mode was built first.

## Revised premise (after grill)

- The failing class is **private proper nouns**, not standard jargon
  (Whisper large-v3 mostly handles "transformer" / "Solana"). The concrete
  case "gbrain → gbrand" is itself a gbrain entity.
- Proper nouns are out-of-vocabulary → the fix must be **injected externally,
  post-decode**. Decode-time biasing is ruled out: the sprint-9 decode-prompt
  spike was rejected because the prompt **leaks** into the transcript
  (commit `ec09b76`), and biasing toward a long term list also degrades
  general accuracy.
- **Single source of truth**: the terms *are* Panda's gbrain entities
  (people / companies / projects). The dictionary should be sourced from
  gbrain, not hand-maintained — this is the real differentiator vs Typeless's
  manual dictionary, and is ROADMAP M4 (gbrain flywheel) made concrete.
- For the narrow non-word-proper-noun error, a **deterministic phonetic /
  edit-distance matcher on-device** is more reliable, cheaper, and lower-risk
  (won't rewrite the whole sentence, no cloud, no leak) than an LLM. The LLM
  glossary is a *second layer* only when segmentation / code-mix also need
  fixing in the same pass.
- Scope locked to **correction** ("fix what I said using my context"), NOT
  **reduction** ("let me say/type less, predict the rest") — the latter would
  turn murmur into a different product and is explicitly out.
- Translate / ask copy-Typeless modes dropped from the near-term focus.

murmur stays a voice→text dictation tool. Premise still load-bearing: **Y** —
grounded by a concrete error case, first-principles decomposition, and
convergence with how Typeless / VoiceInk ("smart replace") observably work.

## Alternatives considered

- A': **deterministic correction × gbrain source (on-device)** — gbrain entity
  list → phonetic/edit-distance match → replace on the raw transcript before
  paste. No cloud, no leak, won't rewrite the sentence. — **Add**
- B': **LLM glossary correction (cloud)** — same gbrain term list injected into
  the Groq enhance prompt; the LLM corrects names + segmentation + code-mix in
  one pass. Second layer, only when segmentation also needs fixing. — **Add**
- C: **correction-capture loop** — one-tap "this was wrong → correct is ___" on
  each result, building a local {heard → intended} corpus that grows the term
  list AND satisfies the BRIEF dictionary gate's "≥3 documented error cases". — **Add**

## Chosen approach

**All three (Panda: "都做").** Build order is dependency-driven, not scope-cut:

1. **A' + C — the on-device foundation.** A' is the correction engine; C is the
   capture loop that feeds it. They share the term-list / corpus data model, so
   they ship together first.
2. **B' — the LLM layer on top.** Reuses A's gbrain term list at the enhance
   step; added once A' proves correction actually lands and when segmentation
   fixing is wanted.

The gbrain term source is shared across A' and B' (single source of truth).

## Scope

In:
- gbrain-sourced proper-noun term list reaching murmur (export/sync mechanism TBD).
- Deterministic on-device correction pass over the transcript (A').
- One-tap correction-capture loop persisting {heard → intended} pairs (C).
- LLM glossary correction layered into the existing Groq enhance step (B').
- A conscious, recorded **override of BRIEF line 216's dictionary gate** — the
  office-hours session IS the BRIEF's prescribed remedy for re-scoping. The
  dictionary is the direct fix for the in-scope #1 priority ("辨識對"), and C
  clears the gate's "≥3 error cases" condition by capturing them.

Out:
- Decode-time biasing (leaks — `ec09b76`).
- Translate mode (built on `feat/m3a-macos-modes`, **not merged**, shelved).
- Ask-about-selected-text / edit-selected-text — needs Accessibility
  selection-read (BRIEF line 84 pre-v0.1 out-of-scope); deferred, separate work.
- "Reduction" / predictive input agent (would redefine what murmur is).
- Standard-jargon accuracy (Whisper handles it) and model-size changes.

## Next skill (recommended)

```
Shape: N-sequential-sprints
Reasoning: A'+C share a data model and ship as one unit; B' depends on A's
           gbrain term list and lands after. Sequential, single-track build.

Recommended skill:
  → /sprint murmur-gbrain-correction-dictionary   (start with A' + C)

Persona for next skill:
  → eng-lead
  Reason: dominant signal is code — on-device matcher, term-list/corpus data
          model, gbrain export, enhance-prompt integration.
```

## Gotchas surfaced

- Decode-prompt biasing leaks into the transcript (sprint-9, `ec09b76`) — do
  not reintroduce it for terms.
- A' runs a string replacement on the transcript: decide whether it runs before
  or after the existing `enhanced()` / `ScriptNormalizer` / `SanityFilter`
  steps so it doesn't fight the Traditional-script guarantee or get sanity-
  dropped. Proper-noun replacement of non-words has low over-correction risk,
  but a term that collides with a real word (rare here) could over-trigger.
- B' adds the term list to the enhance prompt — watch prompt-size limits;
  needs relevance filtering once the gbrain list is large.
- gbrain → murmur term sync is cross-repo (murmur is `~/site/apps/murmur`,
  gbrain content is `~/site/knowledge/brain`). Export mechanism is an open
  question (file artifact at build time vs runtime read vs MCP).
- C depends on Panda actually tapping to correct; value is delayed but compounds.

## Gate Log

- Stage 1 (load context): skipped (--quick); BRIEF / ROADMAP / Core codebase
  pre-loaded in-session.
- Stage 2 (premise challenge): 3 questions (error-layer diagnosis → term-scope →
  correct-vs-reduce). Revealing throughout; no push-once menu needed; no
  escape-hatch.
- Stage 3 (alternatives): offered A/B/C, then revised to A'/B'/C after the
  Typeless + first-principles question; chose all three (Add/Add/Add).
- Stage 4 (premise refresh): premise shifted from "dictionary for jargon" to
  "gbrain-sourced post-decode proper-noun correction"; still load-bearing (Y).
- Stage 5 (output): brief saved to
  docs/briefs/2026-06-01-murmur-gbrain-correction-dictionary.md

## OPEN_QUESTIONS

- gbrain → murmur term-list sync mechanism (build-time export file / runtime
  read / MCP query)?
- A' matcher algorithm: phonetic (Soundex/Metaphone-style) vs edit-distance vs
  hybrid; how to scope it to non-word proper nouns to avoid over-correction?
- Where A' sits in the pipeline relative to enhance / ScriptNormalizer / SanityFilter?
- C's one-tap correction UI: where it surfaces (the result view) and the corpus
  storage format.
- B' term-list relevance filtering once the gbrain entity set is large.
- Disposition of the shelved translate branch (`feat/m3a-macos-modes`): keep on
  ice or delete?
