# Speculative decoding fires, and it makes things slower

## The cause of the silent no-op

`--spec-type` **defaults to `none`**:

```
--spec-type none,draft-simple,draft-eagle3,draft-mtp,draft-dflash,draft-dspark,
          ngram-simple,ngram-map-k,ngram-map-k4v,ngram-mod,ngram-cache
          comma-separated list of types of speculative decoding to use (default: none)
```

So `-md` loads the draft model and the speculative path stays switched off. The earlier
"draft loads and never fires" result was not a broken feature -- it was a **missing flag**, and
the engine never complained, which is why it looked like a defect. It is the same family as the
flash-attention kernel: something is configured and silently does nothing.

With `--spec-type draft-simple --spec-draft-n-max 8`, the draft fires:

```
I slot print_timing: draft acceptance = 0.40000 (  96 accepted /  240 generated), mean len =  4.20
```

## And it is much slower

Same session, same 8B-Q4_K_M target, same prompt, 128 tokens:

| configuration | tok/s |
|---|---|
| no draft | 8.184 / 8.186 / 8.191 |
| `--spec-type draft-simple --spec-draft-n-max 8` | 2.360 / 2.366 / 2.363 |

**3.5x slower.** 40% acceptance with a mean draft length of 4.2 is a real, working acceptance
rate, and it is nowhere near enough to pay for itself: the 0.6B draft has to run on the same
D700 that the 8B target is decoding from, so every drafted token costs GPU time that the
verification step then has to reclaim.

## What this means for Strata's number

Strata publishes 1.6-1.8x from a small draft model. **That does not reproduce on this
machine.** The mechanism works -- it is the same llama.cpp code path, the acceptance rate is
healthy, and the counters are honest -- but the economics are inverted here, because the draft
model competes with the target for one card that is already the bottleneck.

The honest statement is a target to reproduce that this box does not reach, and the reason is
now specific rather than hand-waved: one GPU, no second device to draft on.

Which is another way of saying that **the idle second D700 is what makes this strategy
impossible on this machine** -- and the utilisation card has been saying exactly that in every
run since it was built.

## Method

- Engines: this branch, `fce9e70e`. Target Qwen3-8B-Q4_K_M, draft Qwen3-0.6B-Q8_0.
- `-ngl 99`, `-c 4096`, `-t 8`, `temperature 0`, 128 tokens predicted, 3 trials each.
- The quantity is the engine's own `timings.predicted_per_second`; the acceptance rate and mean
  draft length are the engine's own `print_timing` line.
- Both configurations ran in the same session on the same machine.
- The one thing this does not control: the draft model's own offload settings, which were left
  at the target's. `--spec-draft-n-cpu-moe` and `--spec-draft-n-gpu-layers` exist and were not
  swept, and a CPU-resident draft would change the economics.
