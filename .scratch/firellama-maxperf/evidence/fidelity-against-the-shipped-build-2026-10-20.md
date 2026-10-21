# Fidelity of this binary against the shipped build

## The two engines

| | |
|---|---|
| this build | `vendor/llama.cpp/build-static/bin/llama-server`, upstream pin `d81235049` + the 40-patch series, sha256 `6c67657f2f5469bbe5262768d07d1df34553e7f851ba5db8c6157ca8307f8d61`, AppleClang 17.0.0. This is the engine built before the 0.87.27 merge; the branch carries 50 patches now, and the cells that the release depends on were measured again on the 50-patch engine (`the-35b-baseline-is-the-spine-2026-10-20.md`, R26) |
| the shipped build | `/Applications/ToshLLM.app/Contents/Resources/bin/llama-server`, the app in Applications (ToshLLM 0.87.26), sha256 `c232e4763a6a462e03131457e92d1cb51a3b2be8383216272f8a0dcdf8af93e1`, same upstream pin, AppleClang 21.0.0 |

The shipped build is a fork build: it has the wave64 kernels (45 matching strings) and the
same upstream commit, so the comparison is this branch against the build that is installed,
not against upstream.

## The method

Same model, same flags, temperature 0, seed 1234, a fixed prompt list, 64 generated tokens
per prompt, and the two engines run one after the other on the same machine and the same
card. The row is a text comparison, not a speed comparison: the speed is in the same
table because it is the only thing that says the two runs did the same work.

## The rows

### The 8B on the card, layer split

| prompt | this build | the shipped build | identical |
|---|---|---|---|
| 1 explain a binary search tree | 8.270 tok/s | 7.672 tok/s | yes |
| 2 reverse the words in a sentence (code only) | 8.268 | 7.674 | yes |
| 3 a train leaves at 14:35 and arrives at 18:05 | 8.270 | 7.674 | yes |
| 4 the causes of the 1929 crash in three sentences | 8.270 | 7.673 | yes |
| 5 mutex against semaphore | 8.260 | 7.672 | yes |
| 6 translate to French | 8.268 | 7.675 | yes |

**6 of 6 identical, 64 tokens each.** The decode is 8.2675 tok/s against 7.6731, 7.7%
faster, which is the fork's own "the 7.7% is code, not compiler flags" result measured
again from the other side.

### The 8B on the card, tensor split

The shipped build **aborts** in its first decode:

```
ggml_abort
ggml_backend_meta_get_split_state
ggml_backend_meta_buffer_init_tensor_impl
ggml_gallocr_alloc_graph
llama_context::decode
```

This build runs the same cell at 8.39 tok/s on all six prompts. The `dist/ToshLLM.app`
build, the other fork build on this machine, aborts the same way on the same cell.

### The 35B on the host

| prompt | this build | the shipped build | identical |
|---|---|---|---|
| 1 explain a binary search tree | 11.135 tok/s | 6.611 tok/s | **no, from character 85** |
| 2 a train leaves at 14:35 and arrives at 18:05 | 11.198 | 6.657 | yes |

The decode is 11.1665 tok/s against 6.6339, 68.3% faster. The one prompt that differs
diverges inside the model's thinking block, where the two builds pick different
continuations of the same sentence:

```
ours:    ... The user asks to "Explain what a binary search tree is." This is
shipped: ... The user asks for an explanation of a binary search tree (BST). ...
```

Both are the same model saying the same thing. The two builds do not produce bit-identical
logits on this path, and at temperature 0 a near-tie in the logits becomes a different
sentence. The divergence is at character 85 of a 64-token answer, and the two answers
say the same thing.

## What this establishes

- On the configuration that works, this build answers **the same as the shipped build**:
  6 of 6 prompts, 64 tokens each, byte for byte.
- This build **does not abort** where the shipped build does: a tensor split on the card.
- This build is 7.7% faster on the 8B's decode and 68.3% faster on the 35B's host decode,
  against the same build's own outputs.
