#!/usr/bin/env bash
# One-shot query against Ternary-Bonsai-2-27B-PTQ1_0 via the PrismML llama.cpp
# fork. Run scripts/setup-bonsai2.sh first. Run this on a machine with real
# GPU passthrough.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="${BONSAI_VENDOR_DIR:-$SCRIPT_DIR/vendor/bonsai2}"
GGUF_PATH_FILE="$VENDOR_DIR/gguf-path.txt"
BIN="$VENDOR_DIR/bin/llama-cli"
CTX="${BONSAI_CTX:-4096}"
# -1 = offload all layers to GPU (PTQ1_0 is ~6GB, fits easily on a 24GB card).
# Set BONSAI_NGL=0 to force CPU-only.
NGL="${BONSAI_NGL:--1}"
# Bonsai 2 thinks (CoT) by default ('auto', template-detected, xhigh effort).
# -rea/--reasoning on|off|auto: confirmed present in this fork's llama-cli
# (2026-09-18, `llama-cli --help`). Set BONSAI_REASONING=off for a no-CoT run.
REASONING="${BONSAI_REASONING:-auto}"
# 1 (default) = print only the model's answer, nothing else. The ASCII
# banner/build-info/REPL-help text bypasses normal fd redirection entirely --
# confirmed 2026-09-18: neither 2>/dev/null nor wrapping the call in
# `>/dev/null 2>&1` suppressed it, and none of --simple-io/--log-disable/
# --no-display-prompt/--no-show-timings/-lv 0 helped either. This is the
# readline/libedit pattern of writing UI chrome straight to /dev/tty, which
# ignores fd 1/2 redirection since it isn't going through them. Fix: use
# `setsid` to detach the child from the controlling terminal before it starts
# -- with no controlling tty, its open("/dev/tty") fails and it should fall
# back to plain output. Combined with -o writing the real answer to a file.
# Set BONSAI_QUIET=0 to always get the full normal llama-cli output (e.g. for
# debugging), even for a -st call.
QUIET="${BONSAI_QUIET:-1}"
# Quiet mode swallows the whole terminal transcript, including the "> "
# prompt -- only makes sense for a non-interactive single-shot call. Rather
# than erroring when -st is missing, just fall back to normal (non-quiet)
# mode automatically so interactive use keeps working without needing
# BONSAI_QUIET=0 set by hand.
case " $* " in
  *" -st "*|*" --single-turn "*) ;;
  *) QUIET=0 ;;
esac
OUTPUT_ARGS=()
OUT_FILE=""
if [ "$QUIET" = "1" ]; then
  OUT_FILE=$(mktemp)
  OUTPUT_ARGS=(-o "$OUT_FILE")
fi
# Skips the empty warmup pass before the real prompt -- trades a slightly
# slower/cold first real generation for a faster process start. Model load
# itself (reading the 6GB GGUF off disk/cache into VRAM) is the dominant cost
# per-invocation either way; this only trims the warmup on top of that.
NO_WARMUP="${BONSAI_NO_WARMUP:-1}"
WARMUP_ARGS=()
[ "$NO_WARMUP" = "1" ] && WARMUP_ARGS=(--no-warmup)

# Everything after -- is forwarded to llama-cli verbatim, e.g.:
#   ./scripts/run-bonsai2.sh -- -p 'Hello' -st
# (-st/--single-turn: answer once and exit, instead of dropping into the
# interactive REPL). "$@" already passes -- through untouched, this just
# documents/enforces the convention.
if [ "${1:-}" = "--" ]; then
  shift
fi

[ -x "$BIN" ] || { echo "missing $BIN, run scripts/setup-bonsai2.sh first" >&2; exit 1; }
[ -f "$GGUF_PATH_FILE" ] || { echo "missing $GGUF_PATH_FILE, run scripts/setup-bonsai2.sh first" >&2; exit 1; }
GGUF_PATH=$(cat "$GGUF_PATH_FILE")
[ -f "$GGUF_PATH" ] || { echo "missing $GGUF_PATH (HF cache), run scripts/setup-bonsai2.sh first" >&2; exit 1; }

if [ "$QUIET" = "1" ]; then
  setsid "$BIN" -m "$GGUF_PATH" -ngl "$NGL" -c "$CTX" --reasoning "$REASONING" \
    "${OUTPUT_ARGS[@]}" "${WARMUP_ARGS[@]}" "$@" </dev/null >/dev/null 2>&1
  # -o's file is the whole "User:\n<prompt>\n\nAssistant:\n<answer>" transcript,
  # not just the answer -- keep everything after the last "Assistant:" marker.
  awk '/^Assistant:$/{buf=""; next} {buf = buf $0 ORS} END{printf "%s", buf}' "$OUT_FILE" \
    | sed -e '1{/^$/d}' -e '${/^$/d}'
  rm -f "$OUT_FILE"
else
  "$BIN" -m "$GGUF_PATH" -ngl "$NGL" -c "$CTX" --reasoning "$REASONING" \
    "${WARMUP_ARGS[@]}" "$@"
fi
