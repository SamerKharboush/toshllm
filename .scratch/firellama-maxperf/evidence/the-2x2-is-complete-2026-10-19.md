# The 2x2 is complete: upstream aborts on both ISA variants, this branch serves on both

## The matrix

`-ngl 99 -sm tensor`, 0.6B-Q8_0, same machine, same session.

| | SSE4.2 build | AVX1+F16C build |
|---|---|---|
| **this branch** | **SERVED** (`b8ef1158`) | **SERVED** (`fce9e70e`) |
| **upstream @ pin** | **SIGABRT 134** (shipped DMG) | **SIGABRT 134** (`e063df64`) |

Every cell filled. The two variables that were suspects are both eliminated:

- **ISA**: our SSE2 build serves, so the differentiator is not the ISA.
- **Toolchain / packaging**: upstream built from pristine source at the pin with the same
  compiler and the same ISA flags as our serving build also aborts. So the differentiator is
  not our compiler, not our build flags, and not the shipped binary's packaging.

The variable that remains is the patch series.

## The assertion, quoted

Upstream's own stderr, from the AVX1 build:

```
W common_fit_params: failed to fit params to free device memory:
  llama_params_fit is not implemented for SPLIT_MODE_TENSOR, abort
ggml-backend-meta.cpp:760: GGML_ASSERT(split_states_equal(src_ss[0], src_ss[2])) failed
  ggml_abort + 261
```

`ggml-backend-meta.cpp:760` is upstream code. `split_states_equal(src_ss[0], src_ss[2])` is a
precondition that the split state of the source and destination tensors agree. Patches
`llama/core/0038` converts that family of failures into a named exit 86 that `Server.swift`
answers by retrying with `--split-mode layer`; on the inputs tested here this branch does not
reach the assertion at all.

## What this does and does not establish

**Established:** on this machine, at this pin, with this model, upstream aborts and this branch
serves. That is rung 0 of the ladder and it is now supported by four binaries rather than two.

**Not established:** that the branch splits tensors across both D700s. The 0.6B log names one
device and no per-device allocation. A degenerate split that keeps everything on device 0 would
look exactly like what has been observed. Rungs 1 and 2 are untouched.

**A deviation to record:** upstream's server target requires a downloaded web-UI asset bundle
that is unavailable offline. The `llama-ui-assets` target was replaced with a no-op in the
throwaway worktree and our fork's already-generated `ui.cpp`/`ui.h` were supplied instead. That
concerns the embedded HTTP UI only; no compute path was modified. Upstream's build is shared
(`libggml-cpu.dylib` carries the code, the executable is a 20 KB shim), while ours is static --
so the two are not byte-comparable, and the ISA scans had to be run against the dylibs.

## The toolchain confound, retired

Recorded as required, and now moot: upstream built with the locally-available compiler aborts in
exactly the same frame as the shipped Clang-21 build. Whatever separates the two sides, it is not
the compiler.
