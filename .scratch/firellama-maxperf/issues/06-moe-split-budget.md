# 06 — MoE split-budget sizing

Status: resolved (premise does not hold on this hardware)
Type: task

## Question

Does `AutoMemoryPlan` / `tosh-plan.cpp` size the Dynamic MoE expert bank against the split VRAM
budget (both cards) or against one card?

## Answer

**Against one card — and it does not matter here, because the planner is dormant: no model on
this machine is MoE, so the code path never runs.**

### The measurement

`read_vram` (`tosh-plan.cpp:308`) takes `g_vram_query`, which is set exactly once in
`ggml-metal-device.m:2043` for the **first** device registered:

```objc
if (g_vram_dev == nil) {
    g_vram_dev = dev->mtl_device;
    tosh_dmoe_set_vram_query(ggml_metal_vram_query);
}
```

`tosh_vram_read` (`tosh-dmoe.cpp:167`) then medians three samples of that one card. So
`p.vram_free_mib` (and therefore `p.available_vram_mib` at line 900, and every
`weights_fit` / `c.free_mib` / `c.arena_mib` derived from it) is **one card's free VRAM**, not
the 2x D700 sum. Same for the model probe: `run_probe` keeps `mem[0]` and `mem.back()`, so the
per-device sizing is one GPU plus CPU.

That is a real defect for a split, but it is not live here:

### Why it is dormant

`tosh_plan_apply` returns before any sizing when the model is not MoE
(`tosh-plan.cpp:560`):

```cpp
if (!mi.moe) {
    if (out) *out = p;
    return false;
}
```

and `mi.moe` needs `expert_count > 0 && expert_used_count > 0` (line 185). Confirmed by
running the dry-run planner (`TOSH_AUTO=1 TOSH_AUTO_DRY_RUN=exit`) against the 27B acceptance
model: it emits no plan and no plan file, and the server logs `Tosh MoE: standard`. The 27B
is arch `qwen35`, a ternary dense hybrid — `qwen35.expert_count` is absent, so it is 0.

Neither local model is MoE (0.6B, 4B, 14B Qwen3 dense; 27B qwen35 ternary dense; qwen-image).
So the planner cannot size anything on this machine, and there is no MoE acceptance run to
compare against.

### What would change it

If a MoE model were added here, the budget would be wrong in the *conservative* direction:
`full_gpu` would be rejected for a model that fits across both cards, and the planner would
fall back to `dmoe`/`legacy_offload`. Not a crash — a missed win. The fix is to sum
`read_vram` across registered Metal devices rather than latching the first, and to have
`run_probe` keep the whole `mem` vector instead of `mem[0]`.

## Comments

- 2026-10-02: read the planner, confirmed the one-card read from the source, then confirmed by
  measurement that the path is dormant (no MoE model locally, dry run emits nothing).
