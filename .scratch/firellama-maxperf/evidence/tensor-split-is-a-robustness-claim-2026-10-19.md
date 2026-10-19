# The tensor-split differentiator is narrower than it looked, and it is already built

## The abort frame is upstream code, and we already patched it

`ggml_backend_meta_get_split_state` lives at `vendor/llama.cpp/ggml/src/ggml-backend-meta.cpp`
-- the pinned llama.cpp's multi-device backend, not the Metal backend and not our code. The
baseline aborts there.

The branch under test already carries `patches/llama/core/0038-engine-tensor-split-falls-back-to-layers.patch`,
and the tree confirms it is applied:

```
ggml-backend-meta.cpp:587  // weights have usually already loaded. Report the reason and exit 86,
                           // which the app recognises and retries once with --split-mode layer.
                           // TOSH_TENSOR_SPLIT_STRICT=1 keeps the abort ...
ggml-backend-meta.cpp:599  const char * strict = getenv("TOSH_TENSOR_SPLIT_STRICT");
```

The patch subject says it converted **39** unsatisfiable tensor-split paths from bare aborts to
one helper that names the reason and exits **86**, which `Server.swift` watches for and answers by
retrying with `--split-mode layer`.

## What that makes the claim

Not "tensor split works on ours and aborts on theirs". The honest statement is:

> The shipped build dies with SIGABRT in `ggml_backend_meta_get_split_state` when asked for
> tensor split. This branch reports the reason and exits 86, and the app falls back to layer
> split rather than crashing.

That is a **robustness** claim on a crash the baseline demonstrably has, and it is the one
differentiator this round that rests on a patch we can point at line by line. It is also not a
speed claim, and must not be written as one.

It does not yet establish that *our* build serves tensor split -- it establishes that ours fails
politely. Whether it serves is what the rebuilt binary answers.

## Why the stale bundle hid it

Patch 0038 is a `.cpp` change in the pinned tree. The shipped `dist/ToshLLM.app` is
0.87.24-beta.1 and predates it, which is why testing the stale bundle found a crash the branch
had already fixed. The stale artifact did not just risk a wrong number; it inverted a conclusion.

## Correction to the earlier wave64 note

The `grep -rl "ggml-meta\|backend_meta_get_split_state" patches/` that listed 60-odd patch files
was matching `ggml-metal`, because `ggml-meta` is a prefix of it. That result was meaningless and
is not cited anywhere.
