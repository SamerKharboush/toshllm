# ToshLLM 0.87.31-beta.4 (no-AVX2, AVX1 engine)

Upstream ToshLLM 0.87.31 with this fork's FirePro D700 work on top. Built and measured on a
Mac Pro 6,1: Xeon E5-2697 v2 (AVX, no AVX2/FMA), 64 GB, 2x FirePro D700, macOS 15.8.

## Install

Drag ToshLLM to Applications. **This build needs a CPU with AVX** (Sandy Bridge or later).
It is not upstream's SSE4.2 build, even though its name ends in `-noavx2`. **In-app
updates are off**, because the updater reads upstream's releases: their AVX2 DMG does not
start on these CPUs, and their no-AVX2 DMG does not carry this fork's patches.

## What changed since beta.3

beta.3 left four items uncovered: the row counts between its thresholds, tensor split, 32-lane
cards, and the 35B's DFlash drafter. This beta covers all four.

- **The q4_K and q6_K mat-vec thresholds moved to where the measurements put them** (patch
  `metal/0072`). q4_K takes its sixteen-lane kernel from 12288 rows (was 8192): below that,
  the plain eight-row kernel measured ahead. q6_K takes eight rows from 1792 rows (was 2048).
  No decode shape of the 4B, 8B or 14B lies in either moved range, so on one card and in
  layer split those models run the same kernels as in beta.3.
- **Tensor split was measured** and gains from the rule (table below), with byte-identical text.
- **32-lane cards** cannot reach the rule: both reads of `TOSH_MV_ROWS8_DISABLE` sit inside
  `simd_width == 64` blocks of `ggml-metal-device.cpp`. None was available to measure.
- **The 35B's DFlash drafter** was measured and needs no kernel change. Its Q8_0 kernels are
  about 22 ms of a ~64 ms draft. Most of the draft is the target's output head, which the
  drafter borrows and which runs on the host.

## Measured on the engine this DMG ships

Method:
- engine: llama.cpp `d81235049` plus 82 patches, AVX1 variant, llama-server sha256
  `22a21a08...`; the bundle's ad-hoc-signed copy has identical `__TEXT,__text`,
  `__TEXT,__const`, `__DATA,__data` and `__DATA_CONST,__const`;
- llama-bench `-p 0 -n 128 -r 5 -fa 1`, N = 5, llama-bench discards its own warmup; cells
  alternated with a 10 s gap. "old" is `TOSH_MV_ROWS8_DISABLE=1` on the same binary.

| model | placement | old tg128 t/s | new tg128 t/s |
|---|---|---|---|
| Qwen3-8B Q4_K_M | one card | 8.26 (0.00) | 10.20 (0.00) |
| Qwen3-4B Q6_K | one card | 12.06 (0.00) | 13.84 (0.00) |
| Qwen3-8B Q4_K_M | tensor split, both cards | 13.81 (0.02) | 16.39 (0.03) |
| Qwen3-4B Q6_K | tensor split, both cards | 16.72 (0.01) | 19.10 (0.02) |

Tensor split rows compare tensor split with itself only, not with layer split or one card.

Text: llama-server, greedy, 256 tokens, two prompts. On one card (8B) and in tensor split (4B
and 8B), old and new are byte-identical; the 8B code-prompt text is byte-identical to beta.3's.

Per-kernel bandwidth at the moved thresholds, card 1, `test-backend-ops perf`, N = 5, GB/s:

| shape (k x rows) | old | new | kernel now |
|---|---|---|---|
| q6_K 2048 x 1792 | 28.08 | 38.77 | r8 |
| q4_K 4096 x 8192 | 37.82 | 51.80 | r8 (was L16r8 in beta.3) |
| q4_K 4096 x 10240 | 38.13 | 52.36 | r8 (was L16r8 in beta.3) |
| q4_K 4096 x 12288 | 38.36 | 57.44 | L16r8 |

The 35B on the host (Ornith-1.0-35B Q6_K, `-ngl 0 -c 16384 -t 12`) with magnitude's DFlash
Q8_0 drafter on card 1, 3 drafts per round, greedy, 128 tokens, 4 requests with the first
discarded, N = 3, measured on the same 82-patch source just before the release build: 10.77-10.89 tok/s, 73 of 87 drafts accepted. Drafting took 1835-1866 ms of
each request's 11662-11796 ms of generation. The app's own launch does not use a drafter.

Not run: any 32-lane card; threshold crossovers at other k than 2048 (q6_K) and 4096 (q4_K).

## Gates

- the patch series: 82 of 82 apply;
- the build check: 0 AVX2/FMA mnemonics;
- `test-backend-ops` MUL_MAT, MUL_MAT_ID and FLASH_ATTN_EXT (also with `TOSH_FA_AMD=1`):
  0 FAIL, 3/3 backends, card 1, including new eval cases at both new boundaries;
- the preflight gate on the bundled engine: `-ngl 0` and `-ngl 99` each served 32 tokens, and
  the forced-drop control reads 1;
- `assert_artifact`: engine commit == pin, bundle `0.87.31-beta.4` == VERSION;
- the mounted DMG: version 0.87.31-beta.4, `TOSHNoAVX2` and `TOSHUpdatesDisabled` true,
  `codesign --verify --deep` passes.

DMG sha256: `dbe3ce7ff2d73517c5e5a651b6878e8d2c18a2a2e285101895a9382415f57343`.

The tag is annotated, not signed: the build machine has no gpg and its only SSH key is locked.
