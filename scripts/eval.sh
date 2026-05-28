#!/usr/bin/env bash
# Murmur WER/CER regression gate — BRIEF Quality gate #1.
#
#   scripts/eval.sh --bootstrap-baseline     # first time / after intentional model change
#   scripts/eval.sh                          # CI/release: fail if WER regressed
#
# Default tolerance is 0.0 (any overall WER increase fails). WhisperKit
# decoding is not bit-deterministic across runs, so a hard gate in CI can
# false-positive on jitter — pass e.g. --tolerance 0.005 there. Keep 0.0
# locally right after a bootstrap when you trust the current run.
#
# Real fixtures are recorded by Panda — see docs/eval/RECORDING-KIT.md.
# This script never synthesizes audio.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f docs/eval/fixtures/manifest.json ]]; then
  echo "no docs/eval/fixtures/manifest.json — record fixtures first:" >&2
  echo "  see docs/eval/RECORDING-KIT.md" >&2
  exit 1
fi

exec swift run --package-path Core MurmurEval "$@"
