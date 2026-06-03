---
schema_version: 1
date: 2026-06-03
type: sprint
state: SHIPPED
topic: B' — gbrain proper-noun glossary into the Groq enhance prompt
mode: default
iteration: 2
tags: [sprint, shipped, murmur, groq, enhance, glossary, gbrain, privacy]
---

# Sprint — B' Groq glossary enhance — 2026-06-03

## What

`/sprint` (no topic). Session-start sync locked the topic to the documented next
step from the 2026-06-01 correction brief + project memory: **B' — inject the
gbrain-sourced proper-noun glossary into the existing Groq enhance system
prompt**, layered on top of the already-merged A'+C on-device corrector (PR #6).

A' (deterministic) nails proper-noun *spelling* but is token-level — it cannot
resegment. B' gives the cloud LLM murmur's proper-noun vocabulary so the cleanup
pass can segment + handle code-mix with that context. A' still runs *after*
enhance, so B' cannot regress name-correctness.

Pipeline (order unchanged):
`record → transcribe(raw) → A'.correct(raw) → enhance (NOW glossary-enriched) → A'.correct(cleaned) → paste`

## Decisions

- **Single source of truth.** The glossary is the corrector's *own* deduped term
  universe (gbrain entities + captured-correction `intended` tokens), exposed
  `ProperNounCorrector.glossary` → `CorrectionStore.glossaryTerms` →
  `TextCorrecting`. A' (fuzzy) and B' (LLM) draw from one list, not two.
- **Glossary pulled fresh per enhance call** (`corrector?.glossaryTerms` in
  `DictationCoordinator.enhanced`), so a C capture made this session is in scope
  on the next dictation — not a construction-time snapshot that goes stale.
- **Empty glossary ⇒ byte-identical to the pre-B' prompt**; no `GROQ_API_KEY`
  ⇒ no-op. B' is purely additive and opt-in.
- **Over-correction guard is a prompt clause, not deterministic.** "use these
  exact spellings … do NOT pull unrelated words toward this list." The hard
  guarantee on names stays A's post-enhance deterministic pass.
- **Relevance filtering deferred** (brief already deferred it on size grounds;
  this sprint reframed it as *also* the privacy fix — see below).

## Review (Stage 4 — adversarial multi-agent, 3 dimensions → per-finding skeptic)

6 findings confirmed, 0 rejected (every raw finding survived verification).

- **P1 privacy** — B' transmits the *entire* glossary (holdings, people, private
  projects) to Groq on *every* enhance call, including utterances that mention
  none of them. Distinct from the already-tracked terms.json-at-rest gate: this
  is over-the-wire to a third party. **Disposition (Panda): defer w/ doc.**
  Accepted for personal dogfood (cloud opt-in; Groq already gets the transcript);
  documented in ROADMAP §3; registered as a pre-M6 hard gate (utterance-relevance
  filter) alongside the terms.json gate. → pitfall written.
- **P2** hallucinated-name (LLM may insert an unspoken glossary term; the
  post-enhance A' pass does not strip extras) — accept-with-eyes-open; eval
  regression fixture tracked. Reviewer warned *against* a naive post-enhance
  "strip names not in raw" — it would fight legitimate segmentation, B's point.
- **P3** decode-leak — confirmed NOT a re-intro of the banned decode-prompt leak
  (`ec09b76`); different layer. No action.
- **P3** prompt-size — bounded at 44 terms; no ceiling long-term (relevance
  filter is the single fix for size + privacy + hallucination).
- **COVERAGE_GAP ×2** — empty-glossary test was tautological → pinned to the base
  prompt body (prefix + suffix). `enhance → chat` one-line delegation left
  untested: no URLSession-mock infra exists and the builder + coordinator→enhance
  flow are both covered, so adding mock infra for one delegation line was a
  conscious skip (simplicity-first).

## Terminal state: SHIPPED

PR #7 (`feat/bprime-glossary-enhance`), 9 files, +169/-9. 133 Core tests pass
(+8 for B'). Not auto-merged — Panda merges, as with #6.

## Deferred (tracked, not this sprint)

1. **B' utterance-relevance filter** — pre-M6 privacy hard gate (ROADMAP §3 + M6
   rows). Only inject terms fuzzy-near the actual transcript; subsumes the
   prompt-size concern and shrinks hallucination risk.
2. **terms.json at-rest privacy** — gitignore + build-time bake (pre-existing, M6).
3. **ScriptNormalizer skipped on the Groq cloud-STT fallback path** (P2, pre-existing M1 gap).
4. **P2 eval fixture** — no-proper-noun utterance + populated glossary asserts no
   glossary term appears in enhanced output (catches a future model/prompt regression).

## OPEN_QUESTIONS

- Where the relevance filter sits (in the glossary accessor vs the coordinator
  vs a new pass) — decide when that sprint opens.
- Disposition of the shelved translate branch `feat/m3a-macos-modes` (still open from the brief).
