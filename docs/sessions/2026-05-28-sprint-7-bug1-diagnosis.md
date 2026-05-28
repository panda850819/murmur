---
schema_version: 1
date: 2026-05-28
type: sprint
state: SHIPPED
topic: Sprint 7 — Bug #1 (short Chinese transcription quality), eval-gated
mode: default
iteration: 1
tags: [sprint, shipped, murmur, eval, transcription]
---

# Sprint — Bug #1 short-Chinese transcription quality — 2026-05-28

## Capability probe

All 6 ok (AGENTS / vault / lib / eng-lead persona / swift+xcodebuild+gbrain /
docs write paths). Sprint artifacts write to `docs/sessions/` per murmur
convention, not `Inbox/`.

## Stage progression

| Stage | Status | Output |
|---|---|---|
| 0 capability probe | ok | 6/6 |
| 1 dojo | done | decodeoptions pitfall + eval harness internals + manifest refs |
| 2 grill (lite) | done | 1 fork: language priority → Panda chose **zh-first** |
| 3 execute | done | premise disproved by harness; reverted to baseline (no prod change) |
| 4 review | n/a | no diff to review — investigation outcome, not a code change |
| 5 ship gate | SHIPPED | knowledge deliverable (Direction A: capture & close) |
| 6 terminal | SHIPPED | learning note + session doc + brain backflow |

## What happened

Topic: fix Bug #1 (short Chinese WER), gated by `scripts/eval.sh` vs the v0.1
baseline. Grill surfaced one un-derivable fork — language priority — given the
gate measures overall WER and pinning zh would trade English away. Panda chose
zh-first.

Execute then ran the harness as the oracle and **disproved the plan**:

- `language:"zh"` pin left zh-short identical (0.121) and wrecked English
  (overall 0.113 → 0.169). Language detection was never the residual bug.
- Printing hypotheses exposed the true cause: 「五點半開會」→「5.5開會」 (numeral
  normalization mangling 半), 「三點」→「3點」, 「了」→「的」. Numeral + script +
  minor acoustics, not English leakage.
- `small` model: fixes English (en 0.16 → 0.08) and keeps 半, but emits
  Simplified Chinese (点/开/会/饭) → wrong script for a Traditional writer, zh
  WER worse (0.182).

Conclusion: `base` + `detectLanguage:true` is correct. No production code
shipped — every variant was a measured regression or no-op. The deliverable is
the corrected diagnosis.

## Findings (evidence table)

```
                 zh-short  zh-long   en      overall   script
base + detect    0.121     0.091     0.16    0.113     Traditional   ← kept
pin language:zh  0.121     0.091     0.52    0.169     en wrecked    ← rejected
small + detect   0.182     0.106     0.08    0.121     Simplified    ← rejected
```

## Gate log

- Stage 2 fork (language priority): Panda → zh-first.
- Stage 3 mid-execute fork (premise broke): presented 3 directions (A capture &
  close / B numeral-normalize scorer / C product fix). Panda → **A**.

## Terminal state: SHIPPED (knowledge)

No code change. Artifacts:
- `docs/learnings/pitfalls/2026-05-28-zh-residual-wer-is-numeral-and-script-not-language-detection.md`
- this session doc
- Sprint 7 cross-ref appended to the 2026-05-15 decodeoptions pitfall.

## OPEN_QUESTIONS / scoped follow-up

- **Chinese numeral/time handling + Traditional-script guarantee** — not opened.
  Levers: WER-scorer numeral normalization (3點≡三點), decode prompt biasing
  spelled-out numbers, or small+OpenCC simplified→traditional. Own intake.
- en-01 (0.57 on base) is `base`-model English accuracy, out of Bug #1 scope.
</content>
