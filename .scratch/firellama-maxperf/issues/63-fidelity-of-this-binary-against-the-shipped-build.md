# 63: fidelity of this binary against the shipped build

Status: resolved
Type: task
Spec: ../spec.md (Revision 8)

## Problem

This fork replaces the engine that ships in the app. A faster engine that answers differently
is not a faster engine, and the release has no row saying the two agree. The spec requires
this row before any release, and it has to be a row about the same binary that was measured,
not about a build someone else made.

## Change

Temperature 0, a fixed set of prompts, both binaries, the same model and the same context.
Compare the generated text, not the timings. The shipped build is the engine inside
`ToshLLM.app` (sha256 recorded), not a re-build of it.

## Done when

- One row per prompt, both binaries, the outputs either identical or the difference named.
- The model, the context, the prompt list and both sha256 values in the method line.
- No release ships without this row.

## Answer

**6 of 6 prompts identical, 64 tokens each, and this build is faster.** The evidence is in
`../evidence/fidelity-against-the-shipped-build-2026-10-20.md`.

- The 8B layer split: the same 6 prompts, the same 64 tokens, byte for byte identical.
  This build 8.2675 tok/s against the shipped build's 7.6731, 7.7% faster.
- The 8B tensor split: **the shipped build aborts** in `ggml_backend_meta_get_split_state`
  (the build in `dist/ToshLLM.app` aborts the same way), and this build runs the cell at
  8.39 tok/s.
- The 35B on the host: 1 of 2 prompts identical, the other diverging at character 85,
  inside the think block, where the logits are a near-tie. This build 11.1665 tok/s
  against 6.6339, 68.3% faster.

The method line: the 8B is Qwen3-8B-Q4_K_M, the 35B is Ornith-1.0-35B Q6_K, `-ngl 99 -sm
layer` or `-ngl 0`, `-c 4096 -t 8`, temperature 0, seed 1234. The engines are
`vendor/llama.cpp/build-static/bin/llama-server` (pin `d81235049` plus this fork's
patches, AppleClang 17) and the `llama-server` inside `/Applications/ToshLLM.app`
(sha256 `c232e476...`, AppleClang 21, the 0.87.26 release). One engine after the other, on
the same card, with the same prompt list.