#!/usr/bin/env bash
# Downloads the PrismML llama.cpp fork and the Ternary-Bonsai-2-27B PTQ1_0
# (q1) GGUF. See README.md.
#
# Run this on a machine with real GPU passthrough -- BONSAI_ASSET_TAG must
# match a CUDA runtime your driver actually supports. Check with `nvidia-smi`
# (top-right "CUDA Version: X.Y" is the max runtime your driver supports, not
# your installed toolkit version) before picking a tag newer than 12.8.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="${BONSAI_VENDOR_DIR:-$SCRIPT_DIR/vendor/bonsai2}"
REPO="prism-ml/Ternary-Bonsai-2-27B-gguf"
GGUF_FILE="Ternary-Bonsai-2-27B-PTQ1_0.gguf"
FORK_REPO="PrismML-Eng/llama.cpp"
# "linux-cuda-12.8-x64" (default), "linux-cuda-12.4-x64", "linux-cuda-13.3-x64",
# or "ubuntu-x64" for CPU-only.
ASSET_TAG="${BONSAI_ASSET_TAG:-linux-cuda-12.8-x64}"

mkdir -p "$VENDOR_DIR/bin"
cd "$VENDOR_DIR"
GGUF_PATH_FILE="gguf-path.txt"

if [ ! -x bin/llama-cli ]; then
  echo "== finding latest full release (not a partial cudart-only patch tag) for '$ASSET_TAG' from $FORK_REPO ==" >&2
  # Releases are queried via the public GitHub API directly (no gh auth needed).
  # The newest tag can be a Windows-cudart-only patch release with just 3 assets
  # (seen 2026-09 with tag prism-b10687-5d80cff) -- skip those, take the first
  # release that has an asset matching ASSET_TAG.
  ASSET_URL=$(curl -fsSL "https://api.github.com/repos/$FORK_REPO/releases" | python3 -c "
import json, sys
tag = '$ASSET_TAG'.lower()
releases = json.load(sys.stdin)
for r in releases:
    for a in r['assets']:
        n = a['name'].lower()
        if tag in n:
            print(a['browser_download_url'])
            sys.exit(0)
")
  if [ -z "$ASSET_URL" ]; then
    echo "Could not find an asset matching '$ASSET_TAG' automatically." >&2
    echo "Browse releases at: https://github.com/$FORK_REPO/releases" >&2
    exit 1
  fi
  echo "downloading $ASSET_URL"
  curl -fL "$ASSET_URL" -o llama-build.tar.gz
  tar xzf llama-build.tar.gz -C bin
  # layout inside the tarball isn't guaranteed flat; flatten so bin/llama-cli exists
  if [ ! -f bin/llama-cli ]; then
    found=$(find bin -name 'llama-cli' -type f | head -1)
    [ -n "$found" ] && cp "$(dirname "$found")"/* bin/ 2>/dev/null
  fi
  chmod +x bin/llama-cli bin/llama-server 2>/dev/null || true
fi

if [ ! -f "$GGUF_PATH_FILE" ]; then
  echo "== fetching $GGUF_FILE from HF ($REPO) via the HF cache ==" >&2
  # Goes into the standard HF cache (~/.cache/huggingface/hub), not this repo.
  # Don't parse `hf download`'s stdout for the path -- its human-format output
  # is "  path: /abs/path" (a whole line, not a bare path; broke `tail -1`
  # before) and its exact format isn't a stable contract. Locate the file in
  # the cache directly instead.
  hf download "$REPO" "$GGUF_FILE"
  HF_HOME_DIR="${HF_HOME:-$HOME/.cache/huggingface}"
  # snapshots/<hash>/<file> is a symlink into blobs/, not a regular file --
  # follow symlinks (-L) or plain `find` without -type f misses it entirely.
  find -L "$HF_HOME_DIR/hub" -type f -name "$GGUF_FILE" | head -1 > "$GGUF_PATH_FILE"
fi
GGUF_PATH=$(cat "$GGUF_PATH_FILE")

echo "== setup done =="
echo "binary: $VENDOR_DIR/bin/llama-cli"
echo "model (HF cache): $GGUF_PATH"
echo "run:    ./scripts/run-bonsai2.sh -p 'Hello'"
