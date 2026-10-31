# XeonLLM 0.87.31-beta.5 (no-AVX2, AVX1 engine)

**ToshLLM is now XeonLLM.** This fork of [ToshLLM](https://github.com/engeldlgado/toshllm)
by Engelbert Delgado has its own name, bundle id and repository
(<https://github.com/SamerKharboush/xeonllm>). Upstream ToshLLM 0.87.31 with this fork's
FirePro D700 work on top. Built and measured on a Mac Pro 6,1: Xeon E5-2697 v2 (AVX, no
AVX2/FMA), 64 GB, 2x FirePro D700, macOS 15.8.

## Install

Drag XeonLLM to Applications. **This build needs a CPU with AVX** (Sandy Bridge or later).
It is ad-hoc signed, not notarized: right-click it once and choose **Open**. **In-app updates
are off**, because the updater reads upstream's releases.

**Coming from ToshLLM:** XeonLLM is a new app (bundle id `dev.xeonllm.app`). On its first
launch it **copies** ToshLLM's settings (domain `dev.engel.toshllm`), its Application Support
folder and its Keychain items into its own. Nothing of ToshLLM's is moved or deleted, and the
copy runs once. Caches are not copied; they rebuild.

## What changed since beta.4

- **The rename.** App, bundle, DMG, volume, executable, entitlements, About, menus, logs and
  docs say XeonLLM; the icon carries an X. Engine switches keep their `TOSH_*` names, and so do
  the memory-archive webhook headers and the settings-archive format, which other tools read.
  The About tab and README credit ToshLLM and its author.
- **The 35B's DFlash drafter keeps its own copy of the borrowed output head on its card**
  (patch `spec/0073`). The drafter has no head and borrows the target's (Q6_K, 2048 x 248320,
  397.9 MiB), which sits on the host when the target runs at `-ngl 0`; every draft then ran
  that product on the CPU. The copy is made once at load, costs 397.9 MiB on the drafter's
  card, and falls back to the host with a warning if it does not fit.
  `TOSH_DFLASH_HEAD_HOST=1` keeps the host path.
- **The mat-vec thresholds move with k** (patch `metal/0074`). q6_K takes eight rows from
  1792 rows, or from 1536 at k >= 4096, 1280 at k >= 8192 and 1024 at k >= 12288. q4_K's
  large path also takes sixteen lanes from 6144 rows at k <= 2560. Elsewhere unchanged.
  `TOSH_MV_ROWS8_DISABLE=1` still returns both types to the four-row kernels.

## Measured

Both tables were measured on the dev tree build of this release's source (llama.cpp
`d81235049` plus the series), not on the bundled engine; the bundled engine passed the gates
below.

**Thresholds** (`metal/0074`). Method: `llama-bench -p 0 -n 128 -r 5 -fa 1`, card 1, models
fully on the card; old and new binaries alternated, two rounds, 4 processes per cell,
llama-bench discards its own warmup. "old" is the same tree with the beta.4 q4_K rule. Each
figure is one process's mean of 5; per-process sd <= 0.010.

| model | old tg128 t/s | new tg128 t/s |
|---|---|---|
| Qwen3-4B Q4_K_M | 16.145-16.160 | 16.598-16.608 |
| Nemotron-3.5-Bolt-E4B Q4_K_M | 13.011-13.014 | 13.522-13.531 |

These two are the only models in the test set with a shape the new rule moves (q4_K at k
2560, 9728 and 10240 rows). The q6_K change moves no shape of those models; it rests on the
per-kernel sweep (q6_K r4 vs r8 at k 1024-12288, N = 5 per cell). Greedy 256-token text is
byte-identical old vs new on both models.

**The drafter's head** (`spec/0073`). Method: Ornith-1.0-35B Q6_K `-ngl 0 -c 16384 -t 12`,
Qwen3.6-35B-A3B-DFlash Q8_0 drafter on card 1, `--spec-draft-n-max 3`, llama-server, 128
tokens greedy, 4 requests per server with the first discarded, N = 3 per server. "host" is
`TOSH_DFLASH_HEAD_HOST=1`. Two sets, run at different times, reported separately:

| set | host: tok/s | card: tok/s | host: drafting per request | card: drafting per request |
|---|---|---|---|---|
| A (2 servers per cell) | 11.69-11.85 | 12.35-12.67 | 1722-1781 ms | 1074-1091 ms |
| B (1 server per cell) | 10.75-10.90 | 11.63-11.80 | 1845-1852 ms | 1078-1114 ms |

73 of 87 drafts accepted in every request; every text is byte-identical to plain decoding.

Not run: a 32-lane GPU (none here; both threshold rules sit inside `simd_width == 64`
checks, so they cannot apply there), and the drafter numbers on the bundled engine.

## Gates

- the patch series: 84 of 84 apply to `d81235049`;
- the build check: 0 AVX2/FMA mnemonics;
- `test-backend-ops` on card 1: MUL_MAT 1760/1760, MUL_MAT_ID 873/873, FLASH_ATTN_EXT
  1993/1993 (also 1993/1993 with `TOSH_FA_AMD=1`), with new eval cases at each new boundary;
- the preflight gate on the engine: `-ngl 0` and `-ngl 99` each served 32 tokens, and the
  forced-drop control reads 1;
- `assert_artifact` on the bundle: engine commit == pin, bundle `0.87.31-beta.5` == VERSION;
  the engine's llama-server sha256 `4bde27f8...`, the bundle's signed copy `ed4841fc...` with
  identical `__TEXT,__text`, `__TEXT,__const`, `__DATA,__data` and `__DATA_CONST,__const`;
- `swift test`: 504 tests, 16 skipped, 3 failures, all in the pre-existing
  `MCPStdioTransportTests` race; the 7 migration tests pass;
- the mounted DMG: bundle id `dev.xeonllm.app`, version 0.87.31-beta.5, `TOSHNoAVX2` and
  `TOSHUpdatesDisabled` true, `codesign --verify --deep` passes.

DMG sha256: `da7bcaf1ad34a241544017f33e60f6a1c53a1b2d7e6ef418d52383b4eeb07367`.

The DMG window layout is the previous one with its item and volume names changed; Finder
automation was not available on the build machine to regenerate it, and the window was not
inspected by eye. The tag is annotated, not signed.
