# The 35B placement matrix: the CPU is the fast placement, and three cells are not the model

## What was measured

The spine row is `the-35b-baseline-is-the-spine-2026-10-20.md`: the same model, the same
engine, one device, decode 0.1465 tok/s. Every cell below is a delta against it.

| | |
|---|---|
| engine | this branch's llama-server, upstream pin `d81235049` + the 40-patch series, sha256 `6c67657f2f5469bbe5262768d07d1df34553e7f851ba5db8c6157ca8307f8d61` |
| model | `ornith-1.0-35b-Q6_K.gguf`, 27 GB, `qwen35moe`, 40 blocks, 256 experts, 8 used per token |
| machine | Intel Xeon E5-2697 v2, 12 physical cores, 64 GB RAM, two AMD FirePro D700 (6 GB each) |
| flags | `-ngl 99 -c 4096 -t 8`, `-sm tensor` where the cell says so, temperature 0 |
| protocol | per cell: load, then 2 trials of a 192-token prompt eval and an 8-token decode, then a 24-token decode with the card sampled 6 s in |
| N | 2 per cell. This is a placement sweep, not a rate: the deltas are 2.5x to 76x, and the cell that matters is 76x |
| text check | every cell generated 24 tokens, and the first tokens were compared with the CPU reference (the same model, `-ngl 0`) |

## The matrix

| cell | flags | prompt eval | decode | page-ins in the decode window | card A | card B | text |
|---|---|---|---|---|---|---|---|
| one-device | `-sm tensor`, `GGML_METAL_DEVICE_INDEX=1` | 6.4086 | **0.1450** | 35,813 | 4.45 GB, 41% | 566 MB, 0% | reference |
| two-ts11 | `-ts 1,1`, both devices enrolled | 10.9739 | **0.4387** | 24,382 | 3.93 GB, 96% | 3.81 GB, 99% | reference |
| two-ot-late-cpu | `-ts 1,1 -ot blk.(3[2-9]).ffn_.*_exps.weight=CPU` | 7.3341 | **0.3613** | 35,329 | 6.16 GB, 79% | 2.65 GB, 87% | reference |
| cpu | `-ngl 0` | 23.4130 | **11.1015** | 386 | 340 MB, 0% | 184 MB, 0% | reference |
| two-ncpumoe16 | `-ts 1,1 --n-cpu-moe 16` | 15.9140 | 5.9683 | 446 | 5.48 GB, 0% | 5.60 GB, 0% | **collapses** |
| two-ncpumoe24 | `-ts 1,1 --n-cpu-moe 24` | 19.0095 | 6.8473 | 130 | 3.90 GB, 0% | 4.01 GB, 0% | **collapses** |
| two-ncpumoe32 | `-ts 1,1 --n-cpu-moe 32` | 42.7350 | 10.3336 | 162 | 3.91 GB, 0% | 4.02 GB, 1% | **collapses** |
| two-cmoe | `-ts 1,1 -cmoe` | 36.2357 | 9.8263 | 126 | 1.27 GB, 0% | 1.38 GB, 0% | **collapses** |
| two-ot-late-mtl0 | `-ts 1,1 -ot ...=MTL0_Private` | aborts at load | | | | | |

## What the matrix says

**Enrolling the second card is worth 3.03x on the decode.** `-ts 1,1` with both D700s
enrolled gives 0.4387 tok/s against the one-device cell's 0.1450, and the card shows it:
3.93 GB and 96% activity on one card, 3.81 GB and 99% on the other. Before this round the
second card was never enrolled, so every earlier cell in this project was a one-device cell.

**Putting the late layers' experts on the CPU by hand is worse than the split.** The
`-ot` cell gives 0.3613 tok/s, 18% below the plain two-device split, and it loads the
experts on the CPU with mmap, so the disk and the page cache do the work the VRAM would.

**The CPU is the fast placement for this model, by 76.6x.** The same model, the same
prompt, the same 8 threads, everything on the CPU: 11.1015 tok/s against 0.1450 for the
one-device GPU cell, and 23.4130 tok/s of prompt eval against 6.4086. The page-in row
says why the CPU can do it: 386 pages (1.5 MB) in the decode window against 35,813
(147 MB) for the GPU cell, because the 27 GB of weights stay in the page cache and the
GPU path keeps re-faulting pieces of them.

**Neither the card nor the host is saturated in the slow path.** The one-device cell's
card is 41% busy and the host 17.9% busy across 40 threads. A path that is 76x slower than
the same arithmetic on the CPU, with neither side saturated, is not spending its time on
bandwidth: it is spending it on the dispatch and the per-layer wait of the wave64 path.
That is a statement about the measurement, not a diagnosis of the kernel.

**Three cells are not the model.** `--n-cpu-moe` and `-cmoe` are 34x to 71x faster than the
one-device cell, and they are wrong: see
`the-n-cpu-moe-cells-are-not-the-model-2026-10-20.md`. Their numbers are in this table so
that nobody rediscovers them and quotes them.

**A per-device buffer type is not a place to put a tensor.** `-ot ...=MTL0_Private` aborts
at load with `pre-allocated tensor (blk.32.ffn_down_exps.weight) in a buffer (MTL0_Private)
that cannot run the operation (NONE)`. The override names the buffer, and the scheduler
cannot place the operation in it. `=CPU` loads and runs.

## What this does not establish

- Two trials per cell. The order of the cells is not in doubt; the third decimal is.
- The CPU row is the fastest placement measured here, not the fastest that exists. A
  configuration that keeps the attention and the dense layers on a card and the experts on
  the CPU was not found, because the two knobs that come closest to it (`--n-cpu-moe`,
  `-cmoe`) are broken.
- Nothing here says the GPU path is slow for every model. The 8B dense model decodes at
  8.27 tok/s on one card, and the fork's own measurement put the wave64 work 7.7% above the
  generic path. This is about a 256-expert MoE whose active set is 8 experts per layer.
