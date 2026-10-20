# A 35B-A3B MoE serves on this build, and it uses the 64 GB

## The artifact was already on disk

The models live in subfolders of `/Users/sam/models/`, and the unlock was there:

```
deepreinforce-ai/Ornith-1.0-35B-GGUF/ornith-1.0-35b-Q6_K.gguf    27 GB
```

Read straight from the GGUF header: `general.architecture = qwen35moe`,
`block_count = 40`, `expert_count = 256`, `expert_used_count = 8`,
`context_length = 262144`, `file_type = 18` (Q6_K).

256 experts with 8 used per token is the 3B-active shape. No download was needed, and the
`unsloth/Qwen3.6-35B-A3B-UD-MLX-4bit` folder on the same disk is MLX safetensors, which
llama.cpp cannot read, so the Ornith file is the usable one.

**It loads and serves** on the engine at the pinned commit `d81235049`, at `-ngl 99`. That is
the first MoE of this class to run on this machine.

## The placement matrix, with the utilisation card in every cell

Qwen3-14B does not fit in one card. A 27 GB model certainly does not. This is the regime the
whole effort has been circling.

| cell | served | device A: in-use VRAM | device A: GPU Activity | device B: in-use VRAM | device B: GPU Activity |
|---|---|---|---|---|---|
| `-ngl 99 -sm layer` | yes | 4,154,593,280 B | 27% | 80,633,856 B | **0%** |
| `-ngl 99 -sm tensor` | yes | 4,525,527,040 B | 61% | 80,633,856 B | **0%** |

**Both cells are single-device.** The second D700 holds 80 MB at 0% activity in both, and it is
the *same* 80 MB it held during the 8B run -- the desktop's own allocation, not the model's.

So the honest reading of the matrix:

- **Rung 2 is not reached.** A cell where one device has activity is not a split, and the rule
  this project set for itself says so.
- **The 64 GB is doing the work.** The file is 27 GB and the GPU holds about 4.2-4.5 GB of it.
  The remaining ~22 GB is in host memory. The machine's RAM is not idle and the model is not
  pretending to be small -- it is a 35B MoE running with a quarter of it resident on one D700.
- **`-sm tensor` and `-sm layer` are indistinguishable in placement**, only in activity
  (27% vs 61%). Whatever the split mode changed, it did not move the model to the second card.

## The dense 27B fails, and the failure names a second kernel

`Qwen3.6-27B-NEO-CODE-HERE-2T-OT-Q6_K.gguf` (arch `qwen35`, dense) aborts with the same
data-layout error as the 8B case, but on a **different** kernel:

```
E ggml_metal_library_compile_pipeline: failed to create pipeline state:
  base = 'kernel_flash_attn_ext_vec_amd_dk256_kf16_vf16_w64'
```

`dk256` this time, `dk128` before. So the defect in ticket 56 is not one kernel: it is the AMD
vector flash-attention family, at both head dimensions. That is a systematic build problem, not
a single bad kernel, and it is consistent with the "two modules linked" reading of the build
script, which emits one metallib per kernel source because "they cannot be linked into one
metallib: the sources share helper names".

## What this changes

The premise "we have been optimising a model that fits on one card" was right, and the fix was
not a download. It was looking in the subfolders of the models directory.

What is now established: this build runs a 35B-A3B MoE whose weights do not fit in 12 GB of
VRAM, using the host's 64 GB for the majority of them, on one D700 with the second idle.

What is still open: making the second card work, and the placement matrix with `--n-cpu-moe`,
`-ot` and `-cmoe` on this model.
