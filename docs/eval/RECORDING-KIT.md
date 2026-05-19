# Murmur Eval — Recording Kit (Panda only, ~20 min)

> BRIEF Quality gate #1 needs an **Apple-device-native** fixture set
> (iPhone mic + MacBook mic). It cannot be synthesized — TTS / reused
> clips violate the BRIEF. This is the one step the `/goal` loop cannot
> do for you. Everything else (harness, scoring, baseline math) is built.

## What you produce

10–20 short clips + their verbatim transcripts, dropped into
`docs/eval/fixtures/`, listed in `docs/eval/fixtures/manifest.json`.

## Suggested clip set (12, biased at Bug #1)

| id | lang | device | what to say |
|---|---|---|---|
| zh-short-01..06 | zh | iPhone Voice Memos | 6 short Chinese sentences, ≤ 6 字 each — this is the Bug #1 failure zone (short zh → English) |
| zh-long-01..03 | zh | MacBook mic | 3 longer Chinese sentences, 15–25 字 |
| en-01..03 | en | MacBook mic | 3 English sentences, normal length |

Vary content; don't say the same line twice. Speak naturally, not slowly.

## Steps

1. **iPhone**: Voice Memos → record each `zh-short-*` → Share → save the
   `.m4a` to the Mac.
2. **MacBook**: QuickTime → New Audio Recording, or any recorder, for the
   `zh-long-*` / `en-*` clips.
3. **Convert to 16 kHz mono WAV** (WhisperKit's expected input):
   ```bash
   for f in ~/Desktop/murmur-rec/*.m4a; do
     ffmpeg -i "$f" -ar 16000 -ac 1 "docs/eval/fixtures/$(basename "${f%.*}").wav"
   done
   ```
   (`brew install ffmpeg` if missing.)
4. **Write `docs/eval/fixtures/manifest.json`** — copy
   `manifest.example.json`, one entry per clip. `reference` = exactly
   what you said, verbatim. `tokenization`: `character` for zh (CER),
   `word` for en.
5. **Bootstrap the baseline**:
   ```bash
   scripts/eval.sh --bootstrap-baseline
   ```
   This writes `docs/eval/baseline.json`. Commit fixtures + manifest +
   baseline. Sprint 6 → SHIPPED. The `/goal` loop can then resume Sprint 7
   (Bug #1) and Sprint 8, each gated by `scripts/eval.sh` (no regression).

## Notes

- Fixtures are committed (small, ~16 kHz mono, a few seconds each) so the
  baseline is reproducible. If they get large, switch to git-lfs then.
- Re-recording later changes the baseline — only `--bootstrap-baseline`
  when the change is intentional (new model, deliberately new clip set),
  never to paper over a regression.
