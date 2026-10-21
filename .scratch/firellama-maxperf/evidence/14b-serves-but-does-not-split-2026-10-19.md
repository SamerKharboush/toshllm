# 14B serves at tensor split, and the physics says the split is not happening

## What ran

`ours@AVX1` (`fce9e70e`), Qwen3-14B-Q4_K_M (8.4 GB), `-ngl 99`, `-c 2048`, one sample per mode.

| mode | prompt tok/s | decode tok/s |
|---|---|---|
| `-sm tensor` | 1.00 | 0.99 |
| `-sm layer` | 1.01 | 1.00 |

## Reading 1: the split is degenerate

Per the pre-declared falsifier, unbridged tensor parallelism must **cost** throughput -- every
tensor boundary crosses PCIe with no peer group. Measured `T >= L`: the two modes are 1% apart.
That is the signature of a split that is not splitting, and it agrees with the independent
evidence that the log names **one device**:

```
device 0: AMD Radeon HD - FirePro D700
Meta(MTL0_Private) model buffer size = 8161.75 MiB      <- one aggregate line, no per-device split
```

## Reading 2: the measurement cannot separate the modes at all

Both modes run at ~1 tok/s, which is far below what two D700s should manage for a 14B Q4 model.
Whatever is bounding this -- CPU decode, PCIe thrash across unbridged cards, quantization
fallbacks -- it dominates so completely that a 1% difference between modes is not informative in
either direction. A null result from a saturated instrument is not evidence of absence.

**Both readings must be published together.** Reading 1 alone would overclaim a mechanism;
Reading 2 alone would discard a real signal. What is established is narrower than either: at
this size, on this build, the two split modes are indistinguishable in throughput, and the log
does not show two devices holding the model.

## The existence proof did not close

The 14B result was supposed to settle residency without any log parsing: 8.16 GiB of weights
against `recommendedMaxWorkingSetSize` of 6.44 GB per card, so the weights "must" land on both.

That inference is weaker than it looked, and the weakness is in the premise, not the measurement:
`recommendedMaxWorkingSetSize` is a **recommendation**, not a hard cap. macOS will let a Metal
allocation exceed it and page against system memory. So "it did not fit on one card" does not
follow from "it exceeded the recommended budget", and the existence proof is not an existence
proof.

## Rung reached

| rung | status |
|---|---|
| 0 -- upstream aborts, this branch serves | **established**, 2x2 complete, both ISA variants |
| 1 -- serves on models exceeding one card | **established** (14B serves) |
| 2 -- divides tensors across both D700s | **not established** |
| 3 -- the split's price and payoff | **not established**, and this run cannot reach it |

The publishable sentence is rung 1: *this branch serves tensor split on a 14B model where the
shipped build aborts.* It is not "the fork uses both GPUs at once", and the 1 tok/s figure must
appear next to it, because a capability that runs at 1 tok/s is a capability, not a win.

## What would settle rung 2

Per-device allocation from the engine rather than an aggregate, or a probe that makes the second
D700's absence observable: run with `-sm tensor` and confirm both devices report a non-zero
buffer, or force device 0's budget low enough that a one-device placement must fail. Until one of
those exists, rung 2 stays open.
