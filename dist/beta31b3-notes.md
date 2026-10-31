# ToshLLM 0.87.31-beta.3 (no-AVX2, AVX1 engine)

Upstream ToshLLM 0.87.31 with this fork's FirePro D700 work on top. Built and measured on a
Mac Pro 6,1: Xeon E5-2697 v2 (AVX, no AVX2/FMA), 64 GB, 2x FirePro D700, macOS 15.8.

## Install

Drag ToshLLM to Applications. **This build needs a CPU with AVX** (Sandy Bridge or later).
It is not upstream's SSE4.2 build, even though its name ends in `-noavx2`. **In-app
updates are off**, because the updater reads upstream's releases: their AVX2 DMG does not
start on these CPUs, and their no-AVX2 DMG does not carry this fork's patches.

## What changed

- **Upstream 0.87.31 is in**, with all of its llama.cpp patches. The series is 81 patches
  and applies to a pristine worktree of the pin `d81235049`. Three upstream hunks were
  rebased onto this fork's earlier patches: `metal/0052`, `metal/0054` and `moe/0064`.
- **q6_K and q4_K models decode faster on a 64-lane card.** The decode mat-vec takes eight
  rows per threadgroup on matrices with enough rows, and few-row matrices keep four.
  `TOSH_MV_ROWS8_DISABLE=1` restores the old choice. On every model measured, the text is
  byte-identical to the old choice.
- **DFlash drafts that declare causality per layer now load**, among them magnitude's
  Qwen3.6-35B-A3B drafter.

## Measured on the engine this DMG ships

Method:
- engine: llama.cpp `d81235049` plus 81 patches, AVX1 variant, llama-server sha256
  `4f87c3d8...` (the bundle's ad-hoc-signed copy is `a26b6f93...`; its `__TEXT`, `__DATA`
  and `__DATA_CONST` sections are identical to the build);
- llama-bench `-p 0 -n 128 -fa 1`. llama-bench discards its own warmup. The cells were
  alternated with a 10 s gap. "old" is `TOSH_MV_ROWS8_DISABLE=1` on the same binary.

| model | placement | N | old tg128 t/s | new tg128 t/s |
|---|---|---|---|---|
| Qwen3-8B Q4_K_M | one card | 5 | 8.26 (0.00) | 10.20 (0.00) |
| Qwen3-4B Q6_K | one card | 5 | 12.06 (0.00) | 13.84 (0.00) |
| Qwen3-14B Q4_K_M | layer split, both cards | 3 | 5.08 (0.00) | 6.61 (0.00) |

Text: llama-server, `-c 4096 -fa auto --parallel 1`, greedy, 256 tokens, two prompts, one
request each. Every text is byte-identical to the engine before the upstream merge, and
on that engine identical to the old choice.

The 35B on the host (Ornith-1.0-35B Q6_K):
- launch `-ngl 0 -c 16384 -t 12 -fa auto --load-mode none --parallel 1 --cache-ram 0`,
  `TOSH_FA_AMD=1`, `/completion`, greedy, 128 tokens, 4 requests with the first discarded,
  N = 3;
- plain: 9.95 tok/s (sd 0.22);
- with magnitude's DFlash Q8_0 drafter on card 1 (3 drafts per round): 10.84 tok/s
  (sd 0.04), 73 of 87 drafts accepted;
- both texts are identical to the plain text from before the merge;
- the app's own launch does not use a drafter.

Not run: tensor split, 32-lane cards (the change is gated on 64 lanes, so they are unchanged
by construction, not by measurement), and the row counts between the measured thresholds.
These are the subject of the next beta.

## Gates

- the patch series: 81 of 81 apply;
- the build check: 0 AVX2/FMA mnemonics;
- `test-backend-ops` MUL_MAT, MUL_MAT_ID and FLASH_ATTN_EXT (also with `TOSH_FA_AMD=1`):
  0 FAIL, 3/3 backends, card 1;
- the preflight gate on the bundled engine: `-ngl 0` and `-ngl 99` each served 32 tokens, and
  the forced-drop control reads 1;
- `assert_artifact`: engine commit == pin, bundle `0.87.31-beta.3` == VERSION.

DMG sha256: `b0cbdd89050c577f4620421eb693cc26d38a293ba50fed16c93e0ae4ca2ccc20`.

The tag is annotated, not signed: the build machine has no gpg and its only SSH key is
locked.
