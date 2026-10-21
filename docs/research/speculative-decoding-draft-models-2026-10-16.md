# Speculative-decoding draft models for Qwen3-14B on 2x FirePro D700 (2026-10-16)

Question: is there a draft model that can run alongside `Qwen3-14B-Q4_K_M.gguf` on this fork
(llama.cpp pinned `d8123504938`, engine 0.87.24, 2x D700 GCN 1.0 wave64, 6 GB each), and is it
worth the download?

## Verdict up front

One candidate is worth trying and one experiment should run before it. Nothing else applies.

- **No Qwen3-14B DFlash or DSpark draft exists.** The DFlash family skips 14B entirely.
- **Qwen3-14B has no MTP head**, so MTP is not a candidate at all for this target.
- **`williamliao/Qwen3-14B-EAGLE3-Speculator-GGUF` at Q4_K_M is 855 MB and needs no conversion.**
  That is the only ready-to-run draft for this exact target.
- **The fork's own memory planner rejects both DFlash and DSpark** for this model on this pair at
  default settings (arithmetic reproduced below). The planner is not wired for EAGLE-3 at all, so
  EAGLE-3 would be launched by hand.
- **Run `--spec-type ngram-mod` first.** It needs no model, no download and no VRAM, and it
  exercises the same multi-token verify path a draft model would. If verify does not pay here, an
  855 MB draft will not rescue it.
- **Caveat that limits any expected gain:** this target is Q4_K_M, and 75.7% of its per-token
  weight traffic is Q4_K, which has **no** wave64 ext kernel. Only the 24.3% that is Q6_K reaches
  the fast multi-token path. See "The quantisation gate" below. Do not carry the 15.5 -> 20.9
  figure across from a Q6_K model.

## What this fork already wires

`Sources/Servers/Server.swift:377-388` auto-wires two draft paths and nothing else:

- DFlash: looks for `<model-stem>.dflash.gguf` beside the model (`dflashDraftPath`), then asks
  `DflashMemoryPlanner` for `-ngld`.
- MTP: a separate head file beside the model or in `MTP/` (`mtpDraftPath`), or an embedded head
  detected by `nextn_predict_layers` >= 1 (`modelHasMTP`).

EAGLE-3, DSpark, n-gram and `--spec-default` are **not** auto-wired. They are reachable only
through Extra arguments, which the launcher appends last (`args += extraArgTokens.cli`,
`Server.swift:389`), so a hand-written `--spec-type draft-eagle3 -md ...` overrides nothing and is
appended cleanly. Both auto-paths resolve to `nil` for this model today: there is no
`Qwen3-14B-Q4_K_M.dflash.gguf` and no MTP head.

The pinned binary advertises all eleven types:

```
$ vendor/llama.cpp/build-static/bin/llama-server --help | grep -A1 spec-type
--spec-type none,draft-simple,draft-eagle3,draft-mtp,draft-dflash,draft-dspark,
          ngram-simple,ngram-map-k,ngram-map-k4v,ngram-mod,ngram-cache
```

`vendor/llama.cpp/build-static/bin/llama-server --version` -> `0.6.0-dev (build 11429, commit
d81235049)`, matching the pin.

## Candidate comparison

| candidate | HF repo | draft format | size | needs conversion | fits VRAM | likelihood |
|---|---|---|---|---|---|---|
| **EAGLE-3** (RedHatAI speculator, GGUF) | `williamliao/Qwen3-14B-EAGLE3-Speculator-GGUF` | GGUF arch `eagle3`, Q4_K_M | 855 MB | no | marginal | **best** |
| EAGLE-3 (AngelSlim) | `AngelSlim/Qwen3-14B_eagle3` | `pytorch_model.bin`, `LlamaForCausalLMEagle3` | 1.22 GB | yes, `--target-model-dir` | no | poor |
| DSpark block7 | `deepseek-ai/dspark_qwen3_14b_block7` | `model.safetensors`, `Qwen3DSparkModel` | 6.36 GB (3.42 B params) | yes, `--target-model-dir` | **no** | none |
| EAGLE-3 (deepseek ttt7) | `deepseek-ai/eagle3_qwen3_14b_ttt7` | `model.safetensors`, `Qwen3Eagle3Model` | 3.83 GB | yes | no | poor |
| EAGLE-3 (RedHat, source) | `RedHatAI/Qwen3-14B-speculator.eagle3` | `Eagle3Speculator`, `auto_map` + `trust_remote_code` | - | yes | - | flagged |
| EAGLE-3 (thoughtworks) | `thoughtworks/Qwen3-14B-Eagle3` | `safetensors` | - | yes | no | poor |
| **n-gram map** (no model) | - | built into the engine | 0 | no | yes | **run this first** |
| DFlash | none for Qwen3-14B | - | - | - | - | **does not exist** |
| MTP | none for Qwen3-14B | - | - | - | - | **does not exist** |

Sizes are the `blobs=true` sizes from the HuggingFace API, not estimates.

## 1. DFlash and DSpark for a 14B target

**There is no Qwen3-14B DFlash.** A full listing of `z-lab`'s DFlash repos
(<https://huggingface.co/api/models?author=z-lab&search=DFlash&limit=100>) returns, among others,
`Qwen3-4B-DFlash-b16`, `Qwen3-8B-DFlash-b16`, `Qwen3-Coder-30B-A3B-DFlash`, `Qwen3.5-4B-DFlash`,
`Qwen3.5-9B-DFlash`, `Qwen3.5-27B-DFlash`, `Qwen3.5-35B-A3B-DFlash`, `Qwen3.6-27B-DFlash`,
`Qwen3.6-35B-A3B-DFlash`, `Qwen3.8-27B-DFlash2`. No 14B at any generation.
<https://huggingface.co/api/models?author=z-lab&search=DFlash&limit=100>

**DSpark has a 14B draft**: `deepseek-ai/dspark_qwen3_14b_block7`, 3,416,263,169 BF16 parameters,
`model.safetensors` 6,832,533,210 bytes, architecture `Qwen3DSparkModel`, `num_hidden_layers` 5,
`block_size` 7, `target_layer_ids` `[1, 10, 19, 28, 37]`, `markov_head_type` `vanilla`.
<https://huggingface.co/api/models/deepseek-ai/dspark_qwen3_14b_block7?blobs=true>,
<https://huggingface.co/deepseek-ai/dspark_qwen3_14b_block7/raw/main/config.json>

It has no GGUF. Converting is possible on this pin - `conversion/__init__.py:60` registers
`"Qwen3DSparkModel": "qwen"` - but the local interpreter has neither numpy nor torch
(`python3 -c "import numpy"` and `import torch` both fail), so `convert_hf_to_gguf.py` cannot run
without a `pip install`. That is a real acquisition cost even before the size problem.

**What DFlash requires:** a specific target-trained checkpoint, not a synthesised draft. Upstream
is explicit - "The draft is a small block-diffusion model trained for a specific target (for
example `z-lab/Qwen3-4B-DFlash` for `Qwen/Qwen3-4B`)" and conversion needs `--target-model-dir`
"so it inherits the target's tokenizer and token embeddings".
<https://github.com/ggml-org/llama.cpp/blob/master/docs/speculative.md>

**How llama.cpp detects the type:** `common_speculative_types_from_gguf`
(`vendor/llama.cpp/common/speculative.cpp`) reads `general.architecture`; if it is not `"dflash"`
it looks for a `blk.<n-1>.nextn.eh_proj.weight` tensor and otherwise returns nothing. Inside
`dflash`, the presence of `markov_w1.weight` separates `draft-dspark` from `draft-dflash`.

## 2. EAGLE-3

EAGLE-3 is a one-layer transformer that reads three of the target's hidden states. Upstream lists
`AngelSlim/Qwen3-14B_eagle3` among supported drafts.
<https://github.com/ggml-org/llama.cpp/blob/master/docs/speculative.md>

The runtime demands exactly three extract layers:

```cpp
target_layer_ids_n = llama_model_target_layer_ids_n(model_dft);
if (target_layer_ids_n != 3) {
    throw std::runtime_error("draft model is not eagle3 (expected 3 extract layers, got ...)");
}
```
(`vendor/llama.cpp/common/speculative.cpp:559-564`)

Conversion fills those in: when the draft config has no `eagle_aux_hidden_state_layer_ids`,
`conversion/llama.py:77-81` derives `[2, target_num_layers // 2, target_num_layers - 3]`, which is
exactly three layers for a 40-layer target.

### The ready-to-run one

`williamliao/Qwen3-14B-EAGLE3-Speculator-GGUF`, quantised from
`RedHatAI/Qwen3-14B-speculator.eagle3`. GGUF metadata reports `architecture: eagle3`,
`context_length: 40960`. Files:

| file | bytes | GiB |
|---|---|---|
| `Qwen3-14B-speculator.eagle3-Q4_K_M.gguf` | 854,604,960 | 0.796 |
| `Qwen3-14B-speculator.eagle3-Q8_0.gguf` | 1,480,381,600 | 1.379 |
| `Qwen3-14B-speculator.eagle3-F16.gguf` | 2,781,066,400 | 2.590 |

<https://huggingface.co/api/models/williamliao/Qwen3-14B-EAGLE3-Speculator-GGUF?blobs=true>

The loader in this pin registers `eagle3` as a first-class architecture
(`vendor/llama.cpp/src/llama-arch.cpp:146`, `{ LLM_ARCH_EAGLE3, "eagle3" }`), so this file should
load without conversion.

**Two caveats on this repo, both unverified locally:**
1. 262 downloads, 0 likes, a single maintainer, no issue history. It is not a reference artefact.
2. Nothing confirms it was converted against a llama.cpp at or near `d8123504938`. An EAGLE-3 GGUF
   from a different build may carry a tensor layout this pin rejects. This only surfaces at load.

### Size composition

The RedHatAI source config is a single transformer layer, `num_hidden_layers: 1`, `hidden_size:
5120`, `draft_vocab_size: 32000`, with a `d2t` mapping back to the target vocabulary.
<https://huggingface.co/RedHatAI/Qwen3-14B-speculator.eagle3/raw/main/config.json>

So the 0.796 GiB is not "one transformer layer". It is dominated by the reduced-vocabulary head
(32000 x 5120 = 164 M parameters) and the 151936 x 5120 input embedding. The compute is small;
the VRAM is not.

`AngelSlim/Qwen3-14B_eagle3` is the alternative source: `LlamaForCausalLMEagle3`,
`pytorch_model.bin` 1,219,459,838 bytes.
<https://huggingface.co/api/models/AngelSlim/Qwen3-14B_eagle3?blobs=true>. It needs conversion and
would land larger than the 855 MB file. AngelSlim reports accept length 1.74-1.87 and 93.26 ->
145.33 tok/s mean on Qwen3-14B, on a single H20 with vLLM
(<https://huggingface.co/AngelSlim/Qwen3-14B_eagle3>). Neither figure transfers to a wave64 GCN
pair at batch 1.

## 3. MTP: not applicable to this target

`Qwen/Qwen3-14B`'s `config.json` has no MTP keys - no `nextn_predict_layers`, no
`eagle_aux_hidden_state_layer_ids`, nothing MTP-shaped. It is a plain
`Qwen3ForCausalLM`, 40 layers, `num_key_value_heads` 8.
<https://huggingface.co/Qwen/Qwen3-14B/raw/main/config.json>

The local GGUF confirms it directly. Parsing the header of
`/Users/sam/models/Qwen3-14B-Q4_K_M.gguf` gives 443 tensors and 34 KV pairs; there is **no**
`nextn_predict_layers` key and **zero** tensor names containing `nextn`. A byte scan of the header
region finds no `nextn` string at all.

`ServerSettings.modelHasMTP` (`Sources/Servers/Server.swift:1110`) checks `nextn_predict_layers >= 1`
and falls back to `GGUFMetadataCache.hasNextNTensor`. Both are negative for this file, so the
auto-wired MTP path is correctly inert. `draft-mtp` against this target is not reachable.

## 4. VRAM arithmetic

Explicit, with assumptions stated.

**Nominal budget.** Two D700s at 6 GB each = 12.0 GiB. `SettingsKeys.vramReserve` defaults to
1024 MB (`Sources/Settings/SettingsTab.swift:37`) and the launcher multiplies it by the device
count (`Server.swift:1049`), so the engine reserves 2.0 GiB. Usable: **10.0 GiB**.

**Target weights.** 9,001,753,376 bytes = **8.384 GiB**. Under a tensor split that is 4.19 GiB per
card.

**Target KV cache.** 40 layers x 8 KV heads x 128 head_dim x 2 (K and V) x 2 bytes (f16) =
160 KiB/token, so at ctx 16384 the full cache is 2.50 GiB, 1.25 GiB per card.

| ctx | KV total | per card |
|---|---|---|
| 2048 | 0.31 GiB | 0.16 GiB |
| 4096 | 0.63 GiB | 0.31 GiB |
| 8192 | 1.25 GiB | 0.63 GiB |
| 16384 | 2.50 GiB | 1.25 GiB |

**Per card at ctx 16384, f16 KV:** 4.19 (weights) + 1.25 (KV) = 5.44 GiB against a 6.0 GiB card
and a 5.0 GiB post-reserve allowance. Compute buffers sit on top. There is no single-card baseline
for 14B on this host and never will be - `dist/beta24-notes.md:105` records that.

There is a further hard limit: `maxBufferLength` is 3.5 GiB per D700
(`docs/bench-baseline-2026-09-30.md`). A 4.19 GiB per-card weight shard cannot be one buffer, so
the weights are split, and the split fragments the remaining room.

**What the fork's own planner says.** `DflashMemoryPlanner.plan`
(`Sources/Hardware/Hardware.swift:209`) budgets target weights, both KV caches, compute buffers,
the reserve, and a fixed `draftComputeGB = 1.9` ("the observed worst case on the supported
mainline engine") for the target-linked draft graph. Re-running its arithmetic with this model
(`ncmoe` 0, dense, ctx as tabled, f16 KV scale 1.0):

| draft | ctx | budget | target need | draft fixed | room | draft layers |
|---|---|---|---|---|---|---|
| DSpark 14B (est. 1.80 GiB) | 4096 | 10.00 | 9.54 | 1.94 | **-1.49** | **none** |
| DSpark 14B (est. 1.80 GiB) | 16384 | 10.00 | 9.80 | 2.07 | **-1.86** | **none** |
| EAGLE-3 Q4_K_M (0.796 GiB) | 4096 | 10.00 | 9.54 | 1.91 | **-1.45** | **none** |
| EAGLE-3 Q4_K_M (0.796 GiB) | 16384 | 10.00 | 9.80 | 1.93 | **-1.73** | **none** |

A negative room returns `gpuLayers: nil`, which `dflashSelection` turns into no draft at all. So
the app's own gate would refuse DFlash for this model on this pair at defaults.

**And the planner's target side is optimistic.** Its KV term is `0.021 * ctx / 1024` GiB, which at
ctx 16384 is 0.336 GiB. The real dense cache is 2.50 GiB, 7.4x more. The comment in the source
says the coefficient is "calibrated against the engine's 8K/16K/32K allocations" for hybrid Qwen
KV "where most layers use a sliding window". Qwen3-14B is dense full attention
(`"sliding_window": null`). So the real headroom is worse than the table above shows. Do not read
that table as a comfortable margin.

**Where 855 MB could still land.** Only in a smaller-context, quantised-KV configuration, with the
reserve lowered, and even then only just. It is a squeeze, not a fit.

## 5. The quantisation gate - the finding that caps any gain

This is the part that decides whether speculative decoding is worth anything here.

Upstream cites 27B + DFlash2 on GCN going **15.5 -> 20.9 tok/s**, "up to a third faster", with the
gain attributed to verification: "Reading a prompt and plain generation are unchanged"
(`CHANGELOG.md:652`, fork 0.87.1). That traces to toshllm PR #94, which added wave64-native ext
kernels for the multi-token path (`ne11` 2-12: "speculative verify, small-batch decode"). The PR
measured the old GCN ext path at **~45 GB/s effective** where the wave64-native single-token path
sustains ~265 GB/s (<https://github.com/engeldlgado/toshllm/pull/94>).

Those kernels are gated on quantisation type. From the vendored tree:

```
vendor/llama.cpp/ggml/src/ggml-metal/ggml-metal-ops.cpp:3733
    static const bool ext_w64_disable = TOSH_ENV("TOSH_EXT_W64_DISABLE") != nullptr;
    const bool ext_w64_q6k = !ext_w64_disable &&
                             props_dev->simd_width == 64 && op->src[0]->type == GGML_TYPE_Q6_K;
```

Enumerating the wave64 ext instantiations in
`vendor/llama.cpp/ggml/src/ggml-metal/kernels/mul_mv.metal` gives `q8_0` (r1_2..r1_5) and
`q6_K` (r1_2..r1_5 plus the `r1_8` single-pass form). There is **no `q4_K` wave64 ext kernel**:
`grep -c "kernel_mul_mv_ext_q4_K_f32.*w64"` returns 0.

Now the target. Parsing the type of every tensor in the local
`Qwen3-14B-Q4_K_M.gguf` (443 tensors):

| tensor pattern | type | count |
|---|---|---|
| `blk.N.attn_v.weight` | Q4_K / Q6_K | 20 / 20 |
| `blk.N.ffn_down.weight` | Q4_K / Q6_K | 20 / 20 |
| `output.weight` | Q6_K | 1 |
| `blk.N.attn_q,k,attn_output,ffn_gate,ffn_up.weight` | Q4_K | 200 |
| `token_embd.weight` | Q4_K | 1 |
| norms | F32 | 161 |

Rebuilding the file size from that assignment at 4.5 and 6.5625 bits/weight gives 8.99 GB against
a 9.00 GB file, so the assignment is right. Per-token weight traffic splits:

- **Q4_K: 6.81 GB, 75.7%** - generic wave32-era ext kernel, the ~45 GB/s path
- **Q6_K: 2.19 GB, 24.3%** - wave64 ext kernel, the fast path. 29% of those bytes are the lm_head
  alone.

The upstream figure was measured on **UD-Q6_K**, where 100% of weight traffic takes the fast path.
The PR author reported the collapse himself: "My first end-to-end run used UD-Q4_K_S and showed
only +4.4% and +0.9% ... your kernels are gated on Q6_K, so on a Q4_K_S model only its Q6_K
tensors (the output head) take the new path" (<https://github.com/engeldlgado/toshllm/pull/94>).

Qwen3-14B-Q4_K_M sits between those two: 24.3% of bytes on the fast path, versus roughly 5% for
Q4_K_S. That predicts a real but much smaller gain than +35%. **No percentage is quoted here
deliberately.** Scaling the Q6_K result by a byte fraction would be a modelled ideal, which
`CLAUDE.md` forbids, and the byte fraction is not the time fraction.

The separate 70.0 -> 81.6 tok/s figure is RDNA2. `CHANGELOG.md:1028` sits under a section ending
"Measured on a Radeon RX 6700 XT against 0.84.3" - a 6700 XT is Navi 22, RDNA2, wave32. It does
not transfer to a wave64 GCN 1.0 card.

## 6. CPU placement of the draft

llama.cpp supports it and it is the natural answer to the VRAM squeeze.

`--spec-draft-ngl` / `-ngld` / `--gpu-layers-draft` takes an exact layer count, `auto`, or `all`
(`vendor/llama.cpp/common/arg.cpp:4308-4315`). The value lands on the draft's model params:

```cpp
// common_base_params_to_speculative, vendor/llama.cpp/common/speculative.cpp:3088
result.n_gpu_layers = params_spec.n_gpu_layers;
```

So `-ngld 0` is a fully CPU-resident draft. Related knobs that exist: `--spec-draft-device`
(pin the draft to one GPU; a single-device draft is forced to layer split mode,
`speculative.cpp:3094-3096`), `--spec-draft-threads`, `--spec-draft-cpu-mask`,
`--spec-draft-prio`, `--spec-draft-cache-type-k/v`, `--spec-draft-cpu-moe`.

Two things follow for this machine:

1. **The draft would compete with the target for the same 12 Xeon threads.** The baseline notes
   decode is flat from 8 to 16 threads and falls at 24, so there is idle thread capacity at 12 -
   but that is a fact about *bandwidth-limited* single-stream decode, and a CPU draft matvec is
   compute-bound. Whether the spare threads convert to draft throughput is exactly what needs
   measuring.
2. **EAGLE-3 on CPU pays a device round-trip every draft step.** It reads three target hidden
   states (3 x 5120 floats per token) that live on the GPU, and `llama_set_embeddings_layer_inp`
   (`speculative.cpp:600-613`) also adds extraction work to the *target* forward pass - the pass
   that is already the bottleneck. This cost is on the critical path and is paid on every token,
   accepted or not.

## 7. Does the missing AVX2 matter?

Less than it looks, and this fork already has the right build.

The current `build-static` is the AVX1 variant, not the SSE4.2-only one:

```
GGML_AVX:BOOL=ON     GGML_AVX2:BOOL=OFF     GGML_FMA:BOOL=OFF
GGML_F16C:BOOL=ON    GGML_SSE42:BOOL=ON
```

which is `TOSH_AVX1=1` in `scripts/build-engines.sh:137-140` (SSE4.2 + AVX + F16C on, AVX2/FMA/BMI2
off). `docs/avx1-result-2026-09-30.md` compared the AVX1 and SSE4.2-only builds on Qwen3-4B-Q6_K
tensor split and found no measurable delta at either end (141.72/17.43 against 141.71/17.50; pp
and tg both inside noise), concluding "Keep AVX1 as correct-flags default for Ivy Bridge". The
repo's note that "TOSH_NO_AVX2=1 is required; building without it SIGILLs"
(`docs/bench-baseline-2026-09-30.md:44`) refers to the AVX2-on build SIGILLing on this CPU, which
is why the flag exists; it is not a statement that draft inference needs SSE4.2 only.

So a CPU draft runs on a correctly-flagged AVX1 build and there is no ISA headroom to recover.
Whether it is *fast enough* is a separate, unmeasured question.

## 8. Acquisition summary

| candidate | exact artefact | download | conversion | blocked by |
|---|---|---|---|---|
| **n-gram map** | none | 0 | none | nothing |
| **EAGLE-3 GGUF** | `williamliao/Qwen3-14B-EAGLE3-Speculator-GGUF`, `Qwen3-14B-speculator.eagle3-Q4_K_M.gguf` | 855 MB | none | nothing; VRAM is the squeeze |
| EAGLE-3 AngelSlim | `AngelSlim/Qwen3-14B_eagle3`, `pytorch_model.bin` | 1.22 GB | `--target-model-dir`, needs numpy+torch | size, deps |
| DSpark 14B | `deepseek-ai/dspark_qwen3_14b_block7`, `model.safetensors` | 6.36 GB | `--target-model-dir`, needs numpy+torch | **size**, planner says no |
| EAGLE-3 deepseek | `deepseek-ai/eagle3_qwen3_14b_ttt7` | 3.83 GB | conversion | size, deps |

`RedHatAI/Qwen3-14B-speculator.eagle3` carries an `auto_map` pointing at `eagle3.Eagle3SpeculatorConfig`,
so it needs `trust_remote_code`. It is only relevant as the source for the williamliao GGUF, which
was already converted, so no `trust_remote_code` is needed at inference time.

None of these needs a llama.cpp newer than 0.87.24. `draft-eagle3` is in the pinned binary's
`--spec-type` list, `LLM_ARCH_EAGLE3` exists in the pinned `llama-arch.cpp`, and the converter
registers `Eagle3Speculator` and `LlamaForCausalLMEagle3`.

Download URL for the one that matters:

```
https://huggingface.co/williamliao/Qwen3-14B-EAGLE3-Speculator-GGUF/resolve/main/Qwen3-14B-speculator.eagle3-Q4_K_M.gguf
```

## 9. What to run

### First experiment: n-gram map, no model

This is the control for the whole question. It costs nothing, it needs no VRAM, and it exercises
the same multi-token verify path that every draft model would. If `ne11` 2-5 verification does not
pay on this hardware with these quantisations, the 855 MB draft will not rescue it.

Confirming the control takes effect matters here more than usual. `--spec-type ngram-mod` prints
its own statistics to the server log:

```
draft acceptance rate = 0.70312 (   90 accepted /  128 generated)
statistics ngram_mod: #calls = 810, #gen drafts = 15, #acc drafts = 15, ...
```

(<https://github.com/ggml-org/llama.cpp/blob/master/docs/speculative.md>). Read that line before
reading any tok/s. A `ngram-mod` run that reports zero accepted drafts says nothing about whether a
learned draft would work.

Baseline arm, matching the recorded method
(`dist/beta24-notes.md:94`: `-ngl 99 -c 16384 -t 10 -fa auto`, `GGML_METAL_DEVICES=2`, seed 42,
temperature 0):

```bash
GGML_METAL_DEVICES=2 \
/Users/sam/firellama/vendor/llama.cpp/build-static/bin/llama-server \
  -m /Users/sam/models/Qwen3-14B-Q4_K_M.gguf \
  -c 16384 -t 10 -ngl 99 -fa auto --split-mode tensor \
  --seed 42 --temp 0 --np 1 --port 8080
```

Speculation arm, identical except:

```bash
GGML_METAL_DEVICES=2 \
/Users/sam/firellama/vendor/llama.cpp/build-static/bin/llama-server \
  -m /Users/sam/models/Qwen3-14B-Q4_K_M.gguf \
  -c 16384 -t 10 -ngl 99 -fa auto --split-mode tensor \
  --seed 42 --temp 0 --np 1 --port 8080 \
  --spec-type ngram-mod --spec-ngram-mod-n-match 24 --spec-ngram-mod-n-min 16 --spec-ngram-mod-n-max 32
```

`--spec-ngram-mod-n-min` and `-n-max` are dropped from their 48/64 defaults because upstream notes
that for dense models "you can reduce `--spec-ngram-mod-n-min` and `--spec-ngram-mod-n-max`" - a
32-token block is more than this host can accept in one verify pass.

`llama-bench` cannot do this: it exposes no `--spec-*` flags in this build. Use the SPEED-Bench
client, which upstream documents for exactly this
(<https://github.com/ggml-org/llama.cpp/tree/master/tools/server/bench/speed-bench>):

```bash
pip install -r /Users/sam/firellama/vendor/llama.cpp/tools/server/bench/speed-bench/requirements.txt
python /Users/sam/firellama/vendor/llama.cpp/tools/server/bench/speed-bench/speed_bench.py \
  --url localhost:8080 --bench qualitative --category all --osl 512 --concurrency 1 \
  --output /tmp/speed-baseline.json
```

Then re-run the server with the speculation flag and produce `/tmp/speed-ngrammod.json` from the
same prompts. Report the paired per-category difference and the acceptance rate, not a headline
percentage. A KeepAlive launchd agent (`com.user.llama-server`) should be unloaded for both arms
and reloaded after, exactly as `dist/beta24-notes.md:97` did for the recorded runs.

### Second experiment: EAGLE-3, if the control pays

```bash
GGML_METAL_DEVICES=2 \
/Users/sam/firellama/vendor/llama.cpp/build-static/bin/llama-server \
  -m /Users/sam/models/Qwen3-14B-Q4_K_M.gguf \
  -c 8192 -t 10 -ngl 99 -fa auto --split-mode tensor \
  --seed 42 --temp 0 --np 1 --port 8080 \
  -md /Users/sam/models/Qwen3-14B-speculator.eagle3-Q4_K_M.gguf \
  --spec-type draft-eagle3 --spec-draft-n-max 3 \
  -ngld 0 -td 6 \
  -ctkd q8_0 -ctvd q8_0
```

Four deliberate choices, each a variable held fixed for the next run:

- `--spec-type draft-eagle3` is **required**. `common_speculative_types_from_gguf` handles
  `dflash` and the `nextn` tensor probe only; it returns nothing for arch `eagle3`, so `-md` alone
  leaves the type at `none`.
- `-c 8192` halves the target KV against the 16384 baseline, buying 0.63 GiB for the draft. This
  breaks comparability with the recorded 8.584 tok/s figure, so the paired baseline must be
  re-measured at 8192 in the same session.
- `-ngld 0` keeps the draft off both D700s entirely, which is what the negative planner room above
  forces. The VRAM cost is then the target-linked graph plus KV only.
- `-td 6` gives the draft half the threads and leaves six for the target. 12 and 24 are the other
  two points if this one shows anything.
- `-ctkd q8_0 -ctvd q8_0` halves the draft KV. `kvTypeScale` puts q8_0 at 0.53 of f16
  (`Sources/Hardware/Hardware.swift:264-276`).

If `-ngld 0` loads but drafts slowly, the next single variable is `-ngld 1` (the one transformer
layer plus head stays on a GPU) at `-c 4096`. If the load itself is rejected, the pin-vs-conversion
mismatch is real and there is no 0.87.24-compatible EAGLE-3 GGUF to be had without converting
`AngelSlim/Qwen3-14B_eagle3` locally.

### Do not bother with

- DFlash or DSpark: no Qwen3-14B checkpoint exists, and the fork's planner refuses both anyway.
- MTP: the target has no head and the GGUF carries no `nextn` tensors.

## Not verified

- **The williamliao EAGLE-3 GGUF has not been downloaded or loaded.** Nothing here confirms it
  loads on `d8123504938`, that its tensor layout matches, or that its three target layer ids
  survive conversion.
- **No throughput figure is offered for any speculative configuration on this host.** Every tok/s
  cited above is another machine's: 15.5 -> 20.9 on 2x Radeon Pro Vega II (gfx906, RDNA1, but
  Q6_K), 70.0 -> 81.6 on an RX 6700 XT (RDNA2, wave32), 93.26 -> 145.33 on an H20 (vLLM). None is a
  measurement of this pair with this quantisation.
- **Whether EAGLE-3 hidden-state extraction survives this fork's tensor split is untested.** The
  fork fixed a related tensor-split abort for DFlash in 0.87.1 (`CHANGELOG.md:656`), but EAGLE-3
  extraction on layers 2, 20 and 37 of a two-card split has not been exercised.
- **The exact D700 `vramMB` the fork reads from Metal is not recorded here.** The 12.0 GiB budget
  assumes 6 GB per card as reported in `docs/session-summary-2026-10-01.md:14`. If macOS reports
  less, every number above is optimistic.
- **CPU draft throughput on a no-AVX2/FMA3 Xeon is unmeasured.** Section 7 establishes the build
  is correctly flagged; it does not establish that a CPU draft is fast enough.
- **The DSpark 1.80 GiB Q4_K_M estimate is a guess.** That checkpoint is 6.36 GB of BF16 and has no
  GGUF, so no real quantised size exists to measure. Its exclusion rests on the raw 6.36 GB and the
  planner, not on the estimate.
- The `docs/bench-baseline-2026-09-30.md` standing guard (layer split must not fall below single
  MTL on any model that fits one card) is unaffected by any of this, and should be re-checked
  after any change that touches layer-split behaviour.
