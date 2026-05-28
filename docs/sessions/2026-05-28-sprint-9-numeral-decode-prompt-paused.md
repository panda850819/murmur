# Sprint 9 — numeral decode-prompt spike — 2026-05-28 — PAUSED

## What

`/sprint` on the Sprint 7/8 follow-up: 五點半→「5.5」 (Chinese time numeral mangled).
Fork chosen (A): a decode-side fix via `DecodingOptions.promptTokens`, target output
「五點半」, accepting up-front that decode changes are high-risk (Sprint 7 evidence).

## How it went

- **Stage 1 dojo**: found WhisperKit's prompt mechanism (`promptTokens`/`prefixTokens`,
  `WhisperTokenizer.encode`). Flagged the Sprint-7-shaped risk (Chinese bias could wreck
  English) AND, presciently, prompt leakage — both surfaced before executing.
- **Stage 3 execute**:
  - iter 1: pure-Chinese prompt → fixed 五點半 + 三點, improved English (the Sprint-7
    prediction was wrong — soft prompt ≠ hard language pin), BUT regressed zh/en
    code-switching (merge→Mirage, main→Man).
  - iter 2: added a non-overfit code-switching exemplar to the prompt → code-switching
    recovered (better than baseline), **overall WER 0.113 → 0.0565 (−50%)**, no fixture
    regressed. Re-bootstrapped baseline.
- **Stage 4 review**: cold review (P0) + Codex (P1) **independently** flagged prompt
  leakage. Empirically reproduced: near-silent audio → 「上去之後再 update。」 (prompt
  fragment) pasted. For an auto-paste tool this is a P0. The eval missed it entirely — no
  silence fixture in the set.

## Decision

[reject] / PAUSED. Measured against a standard dictation product (Typeless), the
decode-prompt is the **wrong layer**: it fixes formatting where it can't be applied
safely (leaks, biases all languages, overfit-prone). Standard products do VAD + a
post-processing cleanup layer. Reverted the prompt; baseline restored to 0.1129. No
code shipped.

## Value captured

The −50% WER is real but unshippable on this mechanism. The durable finding (decode
prompt fixes WER but leaks → use post-processing + VAD) is logged so a future session
doesn't re-attempt it:
`docs/learnings/pitfalls/2026-05-28-decode-prompt-fixes-wer-but-leaks-wrong-layer.md`.

## Resume path (two independent pieces, each its own sprint)

1. **VAD / no-speech gate** — never auto-paste on silence (also kills the `[BLANK_AUDIO]`
   paste). Table stakes, independent of numerals.
2. **Post-processing cleanup layer** — numerals (五點半), punctuation, format. Deterministic
   rules or a small LLM, applied to the raw transcript. No decode change, no leakage.

## Terminal state: PAUSED

No code change on main (spike reverted). Diagnostic learning + this session note committed.
Numeral handling remains open, now with a concrete architecture direction.

## See Also

- `docs/learnings/pitfalls/2026-05-28-decode-prompt-fixes-wer-but-leaks-wrong-layer.md`
- `docs/sessions/2026-05-28-sprint-7-bug1-diagnosis.md`
- `docs/sessions/2026-05-28-sprint-8-traditional-script-guarantee.md`
