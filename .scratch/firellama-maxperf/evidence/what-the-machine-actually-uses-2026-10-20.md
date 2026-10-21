# The utilisation card, and what it says the box is doing

## The box

```
Intel(R) Xeon(R) CPU E5-2697 v2 @ 2.70GHz    12 physical cores, 24 logical, 64 GB
```

So the CPU lane's `-t 8` ran on a **12-core** machine. The 5.7% packaging number was measured
at a thread count that is not the physical core count, so it qualifies the absolute numbers.
The thread sweep is now the corrective, and it is the cheapest measurement left.

## The card

`tools/utilcard.sh` reads IORegistry for the AMD drivers' own counters, so it needs no root.
`powermetrics` is not used: it requires sudo, and sudo is not available unattended on this
machine, so a card that depended on it would simply never produce a row. The drivers publish
`GPU Activity(%)`, `Device Utilization %`, `inUseVidMemoryBytes`, `vramFreeBytes`,
`Core Clock(MHz)`, `Memory Clock(MHz)`, `Temperature(C)`, `Total Power(W)` and `VRAM,totalMB`
per device, and those are enough to answer "is the second GPU doing anything".

The card was shown to be non-zero on a live run before it was trusted, and shown to go to
zeros with no pid, so its fields are live rather than decorative.

## What it says: the second D700 is idle

Sampling during prompt processing of Qwen3-8B-Q4_K_M at `-ngl 99 -sm layer`:

| | in-use VRAM | vram free | core clock | mem clock | GPU Activity |
|---|---|---|---|---|---|
| one device | 6,135,795,712 B | **241,856,448 B** | 850 MHz | 1370 MHz | **128%** |
| the other device | 80,633,856 B | 6,111,268,800 B | 300 MHz | 150 MHz | **0%** |

One card is saturated to within 241 MB of its 6 GB, running at 850/1370 MHz with the GPU
reporting 128% activity. The other is at idle clocks, 300/150 MHz, 0% activity, holding 80 MB.

**So the second D700 is not carrying the model.** The box has 12 GB of VRAM and the run used
6.14 GB of it.

## Why this is not yet rung 2, stated precisely

8B-Q4 is 4.7 GB and fits on one card, so `-sm layer` placing it entirely on one device is the
expected behaviour, not a defect. This run shows the card works and that the other device is
visible and idle. It does not show a *split* failing, and it is not evidence against one.

What it does establish, and what nobody had measured before:

1. The machine has 12 physical cores, not the 8 the CPU lane used.
2. One D700 holds 6.14 GB and runs at full clocks; the second is idle at idle clocks.
3. The card can tell the two apart, so rung 2 now has an instrument: a real split must show
   **both** devices with non-zero `inUseVidMemoryBytes` and non-zero `GPU Activity(%)` at the
   same time. That is a stronger test than the log's device lines, which only name devices.

## The 64 GB question, and the flag that does not exist

`--no-mmap` is **not supported at this pin** (0 mentions in `--help`; the engine accepts
`--n-cpu-moe`, `-ot`, `-md`, `--draft-max` and `--split-mode`). The third placement in the
tiering test -- "same, with the expert mmap dropped, to force real RAM residency instead of
page-cache illusion" -- has no flag to stand on. That variant has to be re-specified against a
flag the engine actually accepts, or dropped, and saying so is cheaper than guessing a name.

There is also no 30-35B MoE Q4 on this machine. The largest local model is
Ternary-Bonsai-2-27B-PQ2_0 (27B) and the rest are dense. A model that overflows 12 GB of VRAM
has to be obtained before the 64 GB can be shown to be doing work.

## Strata: policy, not code

Strata cannot run here and its code cannot be ported to this machine. Its own README states the
macOS build requires Apple Silicon M1 or newer and macOS 15 or newer, and the Linux AMD path is
HIP on RX 6800 and newer (RDNA2). A D700 is GCN 1.0 Tahiti, and **HIP has no macOS backend at
all** -- that is a compute stack that does not exist on this OS, not a gate to edit.

What llama.cpp already has is the same three levers at a simpler level: `--n-cpu-moe` for
experts on the CPU, `-ot` for per-tensor placement, and mmap for the page cache. Upstream
ToshLLM already ships Dynamic MoE with disk-expert streaming.

So the verdict is: **policy adopted, code not ported.** Any future ticket proposing a port must
first produce a Strata code path that executes on GCN 1.0.
