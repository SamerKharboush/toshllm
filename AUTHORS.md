# Authors

XeonLLM is a fork of [ToshLLM](https://github.com/engeldlgado/toshllm), which is written by
Engelbert Delgado (<engeldlgado@gmail.com>), except where noted; contact that address for
licence questions about upstream's code. The fork's changes (the AVX1 engine variant, the D700
patches and measurements, the XeonLLM rename) are by
[SamerKharboush](https://github.com/SamerKharboush).

The app under `Sources/` and the engine patches under `patches/` are original work,
licensed GPL-3.0-or-later. They include, among others:

- **ToshGEMM**, the tiled Metal matmul that replaces the simdgroup-matrix path AMD GPUs lack
- **FA-AMD**, the flash-attention decode, tile and prefill kernels written for AMD
- the **wave64 port** for GCN/Vega: reductions, quantized decode, batched mat-vec, prefill
- the **multi-GPU** tensor split, its butterfly all-reduce and the peer/event transports
- the **TurboQuant KV** cache reimplementation
- the **DFlash** speculative planner

They are applied on top of llama.cpp and stable-diffusion.cpp, which carry their own
copyright and MIT licence; those files stay under the terms of their authors.
