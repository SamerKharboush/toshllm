# A bigger model with a higher repack: the 27B Q8_0 on this machine

Ticket: `../issues/67-the-plan-offloads-a-model-the-cpu-does-76x-better.md`. Spec:
`../spec.md` (Revision 8). Date: 2026-10-20.

## What was run

The 35B Q6_K (27 GB) is the spine, and it is a 3B-active MoE. The question this record
answers is what the machine does with a bigger model at a higher repack: dense, 27B, Q8_0,
28.4 GB of weights, 64 GB of RAM, 12 GB of VRAM across two D700s.

The model is `Qwen3.6-27B-Fable-Fus-711-UnHeretic-NM-DAU-NEO-MAX-NEO-Q8_0.gguf`
(28 407 800 000 bytes). The engine's own log calls it "MoE: standard", which is the dense
case: no experts, every weight is touched for every token.

Four placements were run, one after the other, the same model and the same prompt.

| placement | prompt eval | decode | the answer |
|---|---|---|---|
| the host (`-ngl 0`) | 4.9964 tok/s (sd 0.0287, n=3) | 1.5972 tok/s (sd 0.0041, n=3) | coherent: "A binary search tree (BST) is a data structure where each node has" |
| one card (`-ngl 99 -sm tensor`, device 1) | 3.3505 tok/s (sd 0.1097, n=3) | 0.0883 tok/s (sd 0.0058, n=3) | **degenerate**: "A binary search tree (BST000000000" |
| one card, repeated | 2.2817 tok/s (n=1) | 0.0800 tok/s (n=1) | **degenerate**: "0000000000000000" |
| both cards (`-ngl 99 -sm tensor -ts 1,1`) | could not be run | could not be run | the GPU timed out during the load |
| one card, layer split (`-sm layer`) | could not be run | could not be run | the GPU reported an internal error during the load |

The host cell re-faults 37 pages in 10.9 s (the model is in the page cache). The one-card
cell re-faults 31 445 pages in 174 s, 128 MB, 0.74 MB/s: the card holds 4.0 GB of a 28.4 GB
model and the host serves the rest from the disk over and over. The card is 26% busy in
that cell and the decode is 18x slower than the host's. The repeated cell re-faults 42 327
pages in 185 s and gives the same answer in a worse form.

The two cells that could not be run are recorded as such, with the engine's own words:

```
E ggml_metal_synchronize: error: command buffer 1 failed with status 5
E error: Caused GPU Timeout Error (00000002:kIOAccelCommandBufferCallbackErrorTimeout)
ggml_metal_device_event_synchronize: failed to wait for event
```

and, for the layer split:

```
E ggml_metal_synchronize: error: command buffer 0 failed with status 5
E error: Internal Error (e00002bd:Internal Error)
```

## The same model on the shipped build

The build in `/Applications/ToshLLM.app` (the 0.87.26 release) runs the same llama.cpp
commit, `d81235049`, with the fork's earlier patch set and a different compiler
(AppleClang 21 against our 17).

| placement | the shipped build |
|---|---|
| the host (`-ngl 0`) | 1.1659 tok/s (sd 0.0038, n=2), prompt eval 4.6533 tok/s, and the answer is **"0000000000000000"** |
| one card (`-ngl 99 -sm tensor`) | it aborts during the load: `GGML_ASSERT(ret.axis != GGML_BACKEND_SPLIT_AXIS_UNKNOWN)` in `ggml_backend_meta_get_split_state` |

So on the host the shipped build is 27% slower and **computes this model wrong**: every
token is zero. This build answers it. On the card the shipped build cannot run the cell at
all, and this build runs it, wrong as it is.

The same difference shows on a model that fits: the 0.6B Q8_0 on the host answers " 1. 2 2.
3 3. 4 4. 5 5." on this build and " The answer is 2. But why is that the case? ..." on the
shipped build. Both are coherent answers to the same question, and they are not the same
answer: the two CPU paths differ in their rounding, and the difference shows up in the
text. The 35B row (R18) already recorded this: 1 of 2 prompts identical, diverging at
character 85, where the logits are a near-tie.

## What this says about the placement rule

The 35B belongs on the host (R11: 76.6x the one-device decode). This model agrees and adds
the reason: **a model that does not fit in VRAM is not "half on the card", it is a model
whose every token crosses the bus, and on this card the answer that comes back is zeros.**
The one-card cell holds 4 GB of a 28.4 GB model, 26% card activity, 0.0883 tok/s and a
degenerate answer, against 1.5972 tok/s and a coherent answer with everything on the host.

That is the same shape as ticket 66 (the `--n-cpu-moe` and `-cmoe` cells): a placement that
moves part of the model to the host produces a fast, wrong answer. The engine does not
refuse these placements, and it should.

The shipped build's zero answer is a separate defect, recorded in ticket 68. The two are
not the same thing and the record keeps them apart: the shipped build answers zeros on the
**host**, where nothing is split, and this build answers zeros on the **card**, where the
model does not fit.

## Method line

- Machine: `Sams-Mac-Pro`, Intel Mac Pro x86_64, Intel Xeon E5-2697 v2 (12 physical, 24
  logical), 64 GB RAM, two AMD Radeon HD FirePro D700 (GCN 1.0, wave64, 6 GB each), the
  headless one on device 1.
- Engine: `vendor/llama.cpp/build-static/bin/llama-server`, the pin
  `d81235049384534c167caea52b85a694f6103d14` with the fork's 50-patch series (the tree
  the 0.87.27 merge produced), sha256
  `8ebda2454b4df9ac348dc289cc44cb7e82af1885aa1c3c2ea78acbc5550b9d0d`, Apple clang 17, 0
  AVX2/FMA mnemonics. The shipped build is
  `/Applications/ToshLLM.app/Contents/Resources/bin/llama-server`, the same commit with the
  0.87.26 patch set, Apple clang 21.
- Model: Qwen3.6-27B-Fable-Fus-711-UnHeretic-NM-DAU-NEO-MAX-NEO-Q8_0.gguf, 28 407 800 000
  bytes, dense.
- Flags: `-c 4096 -t 8`, temperature 0, seed 1234. The prompt is "Explain what a binary
  search tree is." repeated 24 times (about 190 tokens) with `cache_prompt: false` and
  `n_predict: 1` for the prompt eval, and the same sentence with 16 generated tokens for
  the decode and the text.
- N: 3 per cell for this build, 2 for the shipped build on the host. Warmups: none
  discarded; the host cell's first trial is inside the mean and the model is in the page
  cache in every cell that ran (the one-card cell's 31 445 page-ins are the re-faults of
  the part that does not fit, and they are inside the decode).
- What could not be run: the two-card tensor split and the one-card layer split of this
  model, both of which fail inside the GPU during the load. The engine's messages are
  quoted above.
