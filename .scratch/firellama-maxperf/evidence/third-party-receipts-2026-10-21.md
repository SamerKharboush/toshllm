# Third-party receipts: Strata, AirLLM, Colibri (ticket 51)

Shallow clones, read-only, taken 2026-10-21. Every claim below is a file:line at the commit named.
This pays the "receipts owed" in `strata-policy-not-code-2026-10-20.md`.

| project | commit |
|---|---|
| Niko1221/Strata | `011c9e600a93bbc9fd451c563501b5831c32bbca` |
| lyogavin/airllm | `22d72c46a67c9bf91da0615831fbb619e622c158` |
| JustVugg/colibri | `e0db083cdc9e563e0766cc6fc661ef23c32298e0` |

## Strata: cannot run here

- `README.md:51`: Mac support is "Apple Silicon Mac (M1 or newer, macOS 15 or newer)".
- `docs/MAC.md:24`: "An Apple Silicon Mac (M1 or newer). **Intel Macs cannot run it.**"
- `README.md:49`, `docs/AMD_HIP.md:1-9`: the AMD backend is HIP for gfx1100/1101/1200/1201/1030 (RDNA2 and
  newer); gfx906 has a separate opt-in build (`CMakeLists.txt:70-82`). Nothing covers GCN 1.0 (Tahiti, the D700).
- `docs/INSTALL.md:254`: "AMD cards: Linux only".

**New since the 2026-10-20 note:** Strata has an experimental older-CPU build, `STRATA_ISA_FLOOR=avx`
(`CMakeLists.txt:35-46`, `docs/INSTALL.md:243-261`). It explicitly names Sandy/Ivy Bridge, which is this Xeon's
generation. It does not change the verdict, because it lowers the ISA floor of the *CPU share of the experts*
only, and a GPU backend is still required. Its own measurements of that build were taken by forcing the old
paths on a Ryzen 5 7600 with an RTX 5070, not on a real old CPU (`docs/INSTALL.md:249-254`). What we can reuse
is the design point: when the GPU holds the hot experts, the CPU computes the routed rows on ggml-cpu at the
AVX floor. That is the hybrid path of ticket 66.

## AirLLM: cannot run here

- `air_llm/airllm/auto_model.py:7-11`: on `darwin`, every model goes through `AirLLMLlamaMlx`. MLX has no
  Intel-Mac backend.
- `air_llm/airllm/auto_model.py:31,69-72`: on macOS only `LlamaForCausalLM` and `MistralForCausalLM` are
  accepted, and anything else raises "is not supported on macOS yet". Qwen3.6-35B-A3B (MoE) is refused before
  any download.
- `air_llm/airllm/utils.py:88-100`: off macOS the device order is CUDA, then MPS, then CPU. There is no ROCm,
  Metal-on-AMD or OpenCL path.

The idea it carries (load one layer at a time from disk) is what mmap already does at `-ngl 0` when a
model exceeds RAM. That case is measured, not ported, in Phase 2.5 of the plan.

## Colibri: builds on this OS, with two costs

- `c/Makefile:34-36,47-60`: Darwin is a supported build. The x86 Mac case is named at `c/Makefile:96-99`
  ("older X86_64 Macs ... need to use -march"), and the default passes **no** `-march`, so a plain build
  targets baseline x86-64. Use `ARCH=ivybridge` here.
- `c/Makefile:48-50`: OpenMP comes from Homebrew's libomp, and without it the build is **single-threaded**
  (the pragmas are ignored). This machine has no Homebrew. A single-threaded build is not a fair oracle, so
  libomp must be supplied by hand.
- `c/qgemv.h:28`, `c/qi_gemm.h:30`, `c/qwen36.c:1153`: the fast kernels are `__AVX2__ && __FMA__`; SSE4.1
  and scalar fallbacks exist. On this Xeon Colibri runs its fallback kernels, so a loss would not mean
  "architecturally slower", only slower on AVX1 hardware.
- `c/setup_catalog.py:66-72`: the 35B is Colibri's own int4-gs64 container (23.1 GB), from a third-party
  Hugging Face repo, minimum 10 GB RAM. `docs/qwen36.md:26-29`: the alternative is converting the ~70 GB bf16
  checkpoint. The local `Qwen3.6-35B-A3B-UD-MLX-4bit` is not a documented input.
- `README.md:205`: their own row is "6.0 tok/s on the CPU" for Qwen3.6-35B-A3B on their machine A. It is not
  comparable with R24 (10.1353 tok/s, ornith-1.0-35b Q6_K, this Xeon): different machine, quant and
  weights. These are two observations, not a ratio.

## Configurations that cannot be run

- Strata on any path on this machine (no Apple Silicon, no HIP on macOS, GCN 1.0).
- AirLLM on this machine (MLX-only on darwin; Qwen MoE refused).
- Colibri with OpenMP, until libomp is supplied; Colibri's AVX2/FMA kernels (the CPU lacks them).
