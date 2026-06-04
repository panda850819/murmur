---
schema_version: 1
date: 2026-06-04
type: sprint
state: SHIPPED
topic: B' — utterance-relevance filter for the Groq enhance glossary
mode: default
iteration: 3
tags: [sprint, shipped, murmur, groq, enhance, glossary, privacy, relevance-filter]
---

# Sprint — B' utterance-relevance filter — 2026-06-04

## What

`/sprint` (no topic). Session-start sync + project memory locked the topic to the
recommended next step: the **pre-M6 privacy hard gate** the B' review (PR #7)
surfaced. B' was injecting the FULL gbrain proper-noun glossary (people, holdings,
projects) into Groq's enhance system prompt on *every* call, even when the
utterance named none of those entities — third-party network disclosure.

Fix: before the glossary reaches Groq, narrow it to only the terms actually named
in the utterance. An utterance naming no private entity now ships an empty
glossary, which `GroqClient.cleanupSystemPrompt` already renders byte-identical to
the no-glossary base prompt. One filter collapses three axes: third-party
disclosure, prompt size, LLM hallucinated-name freedom.

PR #7 merged to main first (`727b452`); this sprint branched fresh off main.

## Design

`GlossaryRelevanceFilter.relevant(transcript:glossary:isRealWord:)` — keep a term iff
some Latin token in the (A'-corrected) transcript:
- equals it case-insensitively (genuinely spoken, or A'-canonicalized), OR
- is a fuzzy near-miss AND is not itself a real dictionary word.

Reuses A's Damerau-Levenshtein + `editThreshold` + `CorrectionStore.latinTokens`
(made `nonisolated`). One-line insertion at the enhance seam; returns `[String]`,
no downstream signature change. Filter runs on the A'-corrected `raw` (right match
target). Fails closed on short / CJK-only / token-poor utterances.

## Decisions

- **Threshold off `min(token,term)` length, not term-only.** The clamp is the
  load-bearing invariant: it makes the filter provably no looser than A'
  (which scales off token length and floors fuzzy at 3 chars). Started as
  term-length (grill Q1); the review chain forced the tighten.
- **Real-word guard, shared from A'.** Reversed the initial grill decision to omit
  it. Omitting it optimizes recall but the precision cost IS the privacy leak the
  gate exists to stop (common words like `brain`/`summer` pulled `gbrain`/`Sommet`).
  Guard the transcript TOKEN, exposed via new `TextCorrecting.isRealWord` so A' and
  the filter agree on "real word". Exact-match arm runs BEFORE the guard so a
  real-word entity spoken exactly (`Bob`/`Axis`) is still kept (C escape-hatch).
- **Documented threat-model bound:** the guard is NSSpellChecker, so its verdict
  depends on the host's enabled languages. Same bound A' runs under.

## Process — 3 adversarial review iterations

| iter | change | review verdict |
|---|---|---|
| 1 | built filter (fuzzy-only) | P1: common words leak names → fix |
| 2 | added real-word guard | P1: short non-word token leaks term → fix |
| 3 | min(token,term) clamp | P1: missing recall regression test (no code bug) → test added |

Each cycle found a different real issue; the code converged correct. The recurring
shape (filter looser than A') is captured as a pitfall.

## Verification

- 148 Core tests (+7: privacy leak, short-token, code-mix, multi-term e2e,
  post-A' match-target, nil-corrector, real-word recall-lock).
- Mutation-verified: removing the real-word guard makes 3 privacy tests fail
  (`brain→gbrain`, `sonnet→Sommet`, code-mix reappear) — tests are load-bearing.
- All Core targets build.

## Terminal state: SHIPPED

`71c5313` on `feat/bprime-relevance-filter`, PR #8 → main. Closes the B'
over-the-wire privacy gate (ROADMAP §3).

## Deferred follow-ups (non-blocking)

- Custom high-frequency word list so the guard does not depend on host
  NSSpellChecker enabled languages (the foreign-word P2 bound).
- Multi-word phrase matcher — glossary is single-token by construction today; a
  multi-word entry would fail closed (privacy-safe), not open.
- `minFuzzyLength` forwarding if that knob is ever exposed (currently unreachable:
  no caller sets it, public API can't override → filter stays ≤ A').
- Pre-existing: terms.json at-rest bake gate, ScriptNormalizer on Groq STT
  fallback path, P2 LLM hallucinated-name eval fixture.
