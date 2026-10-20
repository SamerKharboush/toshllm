# The 35B baseline is the spine every later cell is a delta against

## The artifact

| | |
|---|---|
| engine | this branch's llama-server: upstream pin `d81235049` plus the 40-patch series (patch 0039 included, so the attention path is the fixed one), AVX1 ISA flags (this Xeon E5-2697 v2 has no AVX2), sha256 `6c67657f2f5469bbe5262768d07d1df34553e7f851ba5db8c6157ca8307f8d61` |
| model | `/Users/sam/models/deepreinforce-ai/Ornith-1.0-35B-GGUF/ornith-1.0-35b-Q6_K.gguf`, 27 GB, `qwen35moe`, 40 blocks, 256 experts, 8 used per token, Q6_K |
| machine | Intel Xeon E5-2697 v2, 12 physical cores, 64 GB RAM, two AMD FirePro D700 (6 GB each) |
| device | the headless D700 (`GGML_METAL_DEVICE_INDEX=1`); one device, because the backend registers one unless it is told otherwise |
| flags | `-ngl 99 -sm tensor -c 4096 -t 8` |
| N | 5, no warmup discarded: trial 1 (6.3640) is inside the spread of the other four |
| prompts | prompt eval on a 192-token prompt, decode on an 8-token prompt with 32 generated tokens, temperature 0 |

## The numbers

| | mean | sd | n |
|---|---|---|---|
| prompt eval | 6.5073 tok/s | 0.0883 | 5 |
| decode | 0.1465 tok/s | 0.0007 | 5 |

The first run of this row, on the build before patch 0039, read prompt eval 6.4793 (sd
0.0787) and decode 0.1451 (sd 0.0017). The two runs differ by 0.3 and 1.1 of their own
standard deviations, so the patch changed the log and not the speed.

## The card during the decode

`tools/utilcard.sh`, sampled six seconds into a 120-token decode:

| | |
|---|---|
| the card the model is on | 4,444,102,656 B in use, 1,824,034,752 B free, core 850 MHz, memory 1370 MHz, **50% activity**, 77 C |
| the other card | 563,666,944 B in use, 300 MHz core, 150 MHz memory, **0% activity**, 71 C |
| host | 17.9% of 24 logical cores, 40 threads in the process, load average 3.48, swap 1196 MB, CPU speed limit 100% |

(The AMD counters report the two cards as four IORegistry nodes, two per card; the model sits
on the pair that shows 4.44 GB and 50% activity.)

## The pagein row

Two windows, one after the other, on the same warm server:

| window | pages | MB | window | rate |
|---|---|---|---|---|
| idle control, the server up and nothing asked of it | 2,909 | 11.9 | 120.1 s | 24.2 pages/s |
| a warm 32-token decode | 18,093 | 74.1 | 218.6 s | 82.8 pages/s |

The machine pages by itself at 24.2 pages/s, so the decode's own re-faults are the excess:
**12,798 pages, 52.4 MB, 0.24 MB/s**, and 1.64 MB per token.

That is not flat, and it is not streaming either. Streaming the model would be 27 GB per
token; the disk supplied 1.6 MB per token. The model's file pages are served from the page
cache and the 64 GB is doing the work, with the disk asked for the pieces the cache had let
go of.

The control is what makes the row quotable: without it the decode window reads 0.34 MB/s, and
the part of that which is the machine and not the model is not known.

## What this baseline says about where the 35B is bound

- **Not VRAM.** 4.44 GB of a 6 GB card, and there is nowhere else to put 27 GB of weights.
- **Not the disk.** 0.24 MB/s of page-ins against a multi-GB/s device.
- **Not the GPU.** 50% activity at 850 MHz core clock, while the host burns 17.9% of the
  machine across 40 threads.

So the decode is bound by the host side: the 8 experts per layer that do not fit in VRAM are
read and multiplied on the CPU, and that is where the 6.8 s per token goes. Any placement
change that only moves bytes between the two D700s cannot touch that; a change that moves
experts onto the second card can.

## What this does not establish

- One device, by construction. The two-device cells are the placement matrix, and they are
  deltas against this row.
- The prompt-eval figure is for a 192-token prompt. A short prompt measures the fixed cost
  of the first forward pass instead of the throughput: an earlier 8-token prompt on the same
  build gave 0.53 pp tok/s, which is that fixed cost and not a property of the model.
- A launchd-managed 14B server (`-ngl 0 -t 12`, port 8080) runs on this box. It was idle
  through both runs and the 35B is on the headless card, so it is not what the card and the
  page-in rows are about, but it is on the same host and its cost is in every number here.
