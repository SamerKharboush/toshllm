# 04 — Device-env contract (DEVICE_LIST vs DEVICES)

Status: resolved
Type: task

## Question

How should the app guarantee GPU1 actually opens on the layer path, given `GGML_METAL_DEVICE_LIST=0,1` alone leaves MTL1 closed there while `GGML_METAL_DEVICES=2` opens it?

## Answer

**The premise is false. `GGML_METAL_DEVICE_LIST=0,1` alone opens both GPUs on the layer path,
and the app seam is already correct.** The earlier measurement that made this a question was
the harness, not the env.

### Measured, 4B layer split, 12 threads

| env | pp512 | tg64 |
| --- | --- | --- |
| unset (single device) | 77.45 | 11.98 |
| `GGML_METAL_DEVICE_LIST=0,1` | 78.69 | 12.03 |
| `GGML_METAL_DEVICES=2` | 78.79 | 12.04 |

The old claim was "layer with DEVICE_LIST only = single-device numbers (78.6 vs 78.7)". Both
numbers are the same run re-read as a comparison: single is 77.45, and layer-split at 4B is
supposed to buy nothing anyway (CONTEXT.md, split modes). **A 4B layer run cannot distinguish
one GPU from two**, so it can never have been the test for this.

### Measured, 14B layer split — the test that can actually tell

14B-Q4_K_M is 8.38 GiB and one D700 has 6 GB, so it only runs at all if both cards are
carrying layers:

| env | pp512 | tg64 | devices registered |
| --- | --- | --- | --- |
| `GGML_METAL_DEVICE_LIST=0,1` | 21.25 | 5.10 | MTL0 + MTL1 |
| `GGML_METAL_DEVICES=2` | 21.25 | 5.10 | MTL0 + MTL1 |
| unset (single) | did not fit — 8.38 GiB into 6 GB | — | MTL0 only |

`DEVICE_LIST=0,1` alone registers MTL1 and loads a model that cannot fit on one card. That is
the proof, and it is the opposite of what the ticket assumed.

Registration confirmed in the startup log under `DEVICE_LIST` alone:

```
ggml_metal_device_init: GPU name:   MTL0 (AMD Radeon HD - FirePro D700 (dev p0/v0))
ggml_metal_device_init: GPU name:   MTL1 (AMD Radeon HD - FirePro D700 (dev p0/v1))
```

### The seam

`Server.swift:644-658` sets `GGML_METAL_DEVICE_LIST` when `gpuList.count >= 2`,
`GGML_METAL_DEVICES` for count-based `multiGPU`, and `GGML_METAL_DEVICE_INDEX` for a single
pinned GPU. That is correct and needs no change.

### What still stands

The ticket's other requirement does: **the silent-single-GPU outcome must become loud.** A user
who asks for a 2-GPU split and silently gets one GPU has no signal today. Worth a follow-up
ticket: log the registered device count against the requested split at startup, and warn when
they disagree. That is engine-side output the app already parses in `consume()`.

## Comments

- 2026-10-02: resolved. Premise refuted by measurement; the seam is correct. Loud-on-mismatch
  split into a new follow-up.
