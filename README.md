# Ternary Bonsai 2 27B (q1 / PTQ1_0)

Scripts and notes for running [PrismML's Ternary Bonsai 2 27B](https://prismml.com/news/bonsai-2-27b)
at q1 quantization (`PTQ1_0`, ~1.75 bits/weight) via PrismML's llama.cpp fork.

Notes from setting this up on 2026-09-18.

## What it is

- PrismML's Bonsai 2 27B, based on Qwen3.8-27B, announced 2026-09-17.
  https://prismml.com/news/bonsai-2-27b
- Ternary `{-1, 0, +1}` weights with FP16 group-wise (g128) scaling.
- Two GGUF packings on HF (`prism-ml/Ternary-Bonsai-2-27B-gguf`):
  - `PTQ1_0` — dense trits, ~1.75 bits/weight, **5.95 GB** (this is the "q1" build)
  - `PQ2_0` — 2-bit slots, ~2.13 bits/weight, 7.21 GB
- 262K context, multimodal (text+image), tool calling, reasoning mode.

## Running it (llama.cpp fork, CUDA)

Needs a real GPU passthrough — `nvidia-smi`/`nvcc` must resolve on whatever
machine you run these scripts on (they won't work in a GPU-less container).
Check `nvidia-smi`'s top-right "CUDA Version: X.Y" — that's the max CUDA
*runtime* your driver supports, not an installed toolkit version. The fork
ships prebuilt `linux-cuda-12.4`, `linux-cuda-12.8`, and `linux-cuda-13.3`
binaries; pick the highest one your driver actually supports (default here is
`linux-cuda-12.8-x64`; set `BONSAI_ASSET_TAG=linux-cuda-12.4-x64` to go
older/safer, or `ubuntu-x64` for CPU-only).

`scripts/setup-bonsai2.sh` downloads the PrismML llama.cpp fork's CUDA 12.8
binary release and the PTQ1_0 GGUF, then you're ready to run. Deliberately
skips the upstream `Bonsai-demo` repo's own `setup.sh`, since that also pulls
in MLX, Open WebUI, and a full Python/uv env not needed just for inference.

```bash
./scripts/setup-bonsai2.sh          # downloads binary into vendor/bonsai2/, model into HF cache
./scripts/run-bonsai2.sh -p "Hello" # one-shot query, -ngl -1 (full GPU offload) by default
```

PTQ1_0 is ~6GB — fits comfortably on a 24GB GPU (tested on an RTX 3090, ~1.6GB
already in use by desktop/Xorg) with full layer offload.

## Verified release asset

Confirmed via the GitHub API directly (2026-09-18) — don't trust WebFetch-style
page summaries for exact filenames, they can be guessed/pattern-matched rather
than read literally. First run hit this: the *newest* release tag
(`prism-b10687-5d80cff`) turned out to be a Windows-cudart-only patch with just
3 assets, not the full binary matrix. The prior tag (`prism-b10685-7dffb15`,
23 assets) has the real Linux CPU build:

```
llama-prism-b10685-7dffb15-bin-ubuntu-x64.tar.gz   (17 MB, CPU only, no cuda/rocm/vulkan)
```

`scripts/setup-bonsai2.sh` walks releases via `api.github.com` (no `gh auth`
needed) and picks the first release with an asset matching `BONSAI_ASSET_TAG`,
rather than assuming "latest" is a full release.

The GGUF is fetched with `hf download` into the standard HF cache
(`~/.cache/huggingface/hub`), **not** into this repo. The llama.cpp fork binary
is a downloaded build artifact, so `vendor/bonsai2/` — holding the binary plus
a `gguf-path.txt` pointer to the HF cache — is gitignored. Neither
`huggingface-cli` nor `pip` is required; `hf` (the current `huggingface_hub`
CLI) is what's used.

## Disabling thinking (CoT)

Verified against `llama-cli --help` in this fork (2026-09-18, tag
`prism-b10685-7dffb15`):

- `-rea, --reasoning [on|off|auto]` — direct toggle, default `auto`
  (template-detected). `./scripts/run-bonsai2.sh` passes this through via
  `BONSAI_REASONING` (default `auto`); set `BONSAI_REASONING=off` for a no-CoT run.
- `--reasoning-effort LEVEL` — `minimal|low|medium|high|xhigh|max`, template default
  is `xhigh` per PrismML's page. Lower this instead of fully disabling if you want
  *some* thinking but less latency.
- `--reasoning-budget N` — token cap on the thinking trace (`0` = end immediately,
  `-1` = unrestricted). An alternative to `--reasoning off` — the upstream demo
  repo's docs only mention this one, for `start_llama_server.sh`, not the
  cleaner `--reasoning` flag; both exist in this build.

```bash
./scripts/run-bonsai2.sh -p 'Hello' -st -rea off
```

## Speed / quiet output

First real run (2026-09-18, `-p 'Hello' -st -rea off`): 2.78s wall total on
an RTX 3090, most of it model load (72 t/s prompt, 52 t/s generation once
running). `run-bonsai2.sh` defaults to:

- `BONSAI_QUIET=1` (default) — prints only the model's answer. Tried three
  approaches in order on host (2026-09-18), first two failed:
  1. Flags (`--simple-io --log-disable --no-display-prompt --no-show-timings
     -lv 0`) — none suppressed the banner.
  2. Wrapping the call in `>/dev/null 2>&1` — **still didn't suppress it**,
     even though it's not going to a log file. This means the ASCII
     banner/build-info/REPL-help block bypasses fd 1/2 redirection entirely —
     the readline/libedit pattern of writing UI chrome straight to
     `/dev/tty`, which ignores normal stdout/stderr redirection.
  3. **Fix that worked**: `setsid` to detach the child from the controlling
     terminal before it starts. With no controlling tty, `open("/dev/tty")`
     fails and llama-cli falls back to plain output. Combined with `-o FNAME`
     (writes the real answer to a file) and `cat`ing that file afterward.
  `-o`'s file turned out to hold the whole `User:\n<prompt>\n\nAssistant:\n
  <answer>` transcript, not just the answer — the script `awk`s out
  everything after the last `Assistant:` marker before printing it.
  Only makes sense for a non-interactive `-st` call, so the script
  auto-detects `-st`/`--single-turn` in the forwarded args and silently falls
  back to normal (non-quiet) mode when it's absent — no error, interactive
  use (no `-st`) just works as before. Force full output on a `-st` call too
  with `BONSAI_QUIET=0`.
- `BONSAI_NO_WARMUP=1` — skips llama.cpp's empty warmup pass before the real
  prompt, trims a bit off process start at the cost of a colder first token.

Model load time itself (reading the 6GB GGUF into VRAM) is the dominant cost
of *each invocation*, since each call is a fresh one-shot process rather than
a persistent `llama-server` (which would load once and serve queries over
localhost with near-zero per-query overhead) — that tradeoff was chosen
deliberately in favor of simplicity over that latency win.

## Shell functions

`scripts/bonsai2-bashrc-snippet.sh` has `bonsai2`/`bonsai2-think` wrapper
functions (no-CoT / CoT) to add to your `~/.bashrc`:

```bash
cat scripts/bonsai2-bashrc-snippet.sh >> ~/.bashrc
source ~/.bashrc
bonsai2 -p "How many r's are in the word strawberry?"
```

## Open questions / not yet verified

- Whether PTQ1_0 needs `-fa on` (flash attention) on CPU builds, or if that flag
  is CUDA-only in this fork.
- Benchmark quality (98.2% of full-precision claimed by PrismML, unverified here).
- Extracted tarball layout (whether `llama-cli` is at the tar root or nested) —
  setup script handles either case, but hasn't been exercised for every asset tag.
