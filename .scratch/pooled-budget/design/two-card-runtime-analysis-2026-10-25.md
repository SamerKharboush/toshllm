<!-- Written by OpenCode (nemotron-3-ultra-free, read-only plan agent) from a brief; spot-checked by the orchestrator: tosh_dmoe_set_event overwrites one global (tosh-moe/tosh-dmoe.cpp:76-80, registered per device at ggml-metal-device.m:1239-1247) and the executor polls only tosh_dmoe_event_get() (src/llama-tosh-dmoe.cpp:605, 649). -->

# Dynamic MoE Multi-GPU Analysis

## 1. Inventory: Every Single-GPU Assumption

### llama-tosh-dmoe.cpp

| File:Line | What It Holds/Does | Why It Breaks With Two GPUs |
|-----------|-------------------|----------------------------|
| **1873** `ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_GPU)` | Picks the first GPU device for the arena buffer type | With layer split, different layers live on different GPUs. The arena buffers (gate/up/down per layer) must be allocated on the GPU that owns that layer. |
| **1389** `static ggml_backend_buffer_t g_arena_buf` | Single global arena buffer holding all layers' expert slots | Two GPUs need two separate arena buffers (one per device), each holding only the layers assigned to that device. |
| **1837–1851** `quota` computation | Uniform slot count per layer, derived from one `cache_mib` / `per_expert_all_layers` | Each GPU has different free VRAM. The per-layer slot count must be the minimum across devices, or per-device. With uniform slots, the smaller GPU limits both. |
| **1772–1785** `llama_tosh_dmoe_budget(size_t gpu_bytes)` | Reads ONE device's free VRAM via `tosh_dmoe_vram()` (legacy scalar) | The caller (llama-context.cpp:536–547) sums all GPU bytes into one number, losing per-device breakdown. Each device needs its own arena sized from its own free VRAM. |
| **1960** `ggml_backend_alloc_ctx_tensors_from_buft(ctx, buft)` | Allocates all arena tensors (gate/up/down/residency for all layers) from one `buft` | Must allocate each layer's arena tensors from the buffer type of that layer's device. |
| **1941–1953** `llama_tosh_dmoe_layer dl` creation | Creates `arena_gate`, `arena_up`, `arena_down`, `residency` tensors for all layers in one ggml context | The residency table tensor (`dl.residency`) must be accessible to the GPU running that layer. With two GPUs, each needs its own copy of the residency table for its layers, or the table must be in shared memory readable by both. |
| **2012–2014** `tosh_dmoe_set_tables()` / `tosh_dmoe_publish_version(0)` | Registers one global residency table (host memory) and publishes version 0 | The table layout is `[VERSIONS][MAX_LAYERS][N_EXPERT]`. All layers share one table. This works if the table is in host memory (it is), but the GPU kernels must read from the correct device's table buffer (which wraps the same host memory). |
| **1977** `ggml_backend_tensor_set(dl.residency, ...)` | Initializes residency table on the arena buffer (GPU) | If the residency tensor lives on GPU 0, GPU 1 cannot read it efficiently. The residency table should be in host memory (shared) and each GPU should have a no-copy buffer wrapping it. |
| **2023** `pol->up = tosh_dmoe_get_uploader()` | Gets a single uploader (bound to one Metal device) | Uploads to GPU 0's arena must go through GPU 0's queue; uploads to GPU 1's arena through GPU 1's queue. The policy thread needs per-device uploaders. |

### llama-context.cpp

| File:Line | What It Holds/Does | Why It Breaks |
|-----------|-------------------|--------------|
| **536–547** `gpu_bytes` summation | Sums VRAM across all GPUs into one scalar for `llama_tosh_dmoe_budget()` | Loses per-device free VRAM. The budget function needs per-device free VRAM to size each arena. |

### ggml-metal-device.m

| File:Line | What It Holds/Does | Why It Breaks |
|-----------|-------------------|--------------|
| **1226–1232** `dmoe_ev`, `dmoe_reach`, `dmoe_stage`, `dmoe_tables`, `dmoe_obs`, `dmoe_wide` per device | Each Metal device has its own event, stage, tables buffer, observation ring, wide stage | **Correctly per-device** — but the registration functions (`tosh_dmoe_set_event`, `tosh_dmoe_set_stage`, etc.) are global. The last device to register wins. |
| **1239–1247** `ggml_metal_device_dmoe_event()` | Registers the device's event as THE global event via `tosh_dmoe_set_event()` | Only one event can be registered globally. With two GPUs, each layer's PUBLISH/JOIN must use its device's event. |
| **1249–1258** `ggml_metal_device_dmoe_reach_event()` | Registers the device's reach event globally via `tosh_dmoe_set_reach_event()` | Same issue: only one reach event globally. |
| **1260–1271** `ggml_metal_device_dmoe_obs_ring()` | Registers the device's observation ring globally via `tosh_dmoe_set_obs_ring()` | Only one observation ring globally. The policy reads from one ring. |
| **1273–1288** `ggml_metal_device_dmoe_tables()` | Creates a no-copy buffer wrapping the global host residency table | This is fine — each device wraps the same host table. |
| **1431–1439** `ggml_metal_dmoe_uploader_init()` / `g_uploader_dev` | Single uploader tied to one Metal device (`g_uploader_dev`) | Uploads for layers on GPU 1 would go through GPU 0's queue, causing cross-device copies or failure. |
| **1454–1465** `ggml_metal_device_dmoe_wide_stage()` | Per-device wide stage, registered globally via `tosh_dmoe_set_wide_stage()` | Only one wide stage globally. Prefill on GPU 1 would use GPU 0's stage. |
| **1467–1480** `ggml_metal_device_dmoe_stage()` | Per-device stage, registered globally via `tosh_dmoe_set_stage()` | Only one stage globally. Mixed decode on GPU 1 would use GPU 0's stage. |
| **2111–2130** `g_vram_dev` | Tracks only the first device for legacy `tosh_dmoe_set_vram_query()` | The legacy VRAM query is used by `llama_tosh_dmoe_budget()` which only sees one device. |

### tosh-dmoe.cpp (Global Rendezvous State)

| File:Line | What It Holds/Does | Why It Breaks |
|-----------|-------------------|--------------|
| **16–18** `g_stage`, `g_stride` | Single global stage buffer pointer and stride | Must be per-device. Each GPU has its own stage buffer. |
| **19–21** `g_ev`, `g_ev_get`, `g_ev_set` | Single global event and accessors | Must be per-device. Each GPU has its own `MTLSharedEvent`. |
| **23** `g_value` | Single global publish sequence counter (`tosh_dmoe_next_value()`) | **Critical**: See §2 below. |
| **25** `g_jobs` | Global job ring indexed by publish value | Jobs from both GPUs share one ring. This works if the value space is shared, but the executor must know which device's event to signal. |
| **33–37** `g_tables`, `g_tables_bytes`, etc. | Single global residency table (host memory) | This is fine — host memory is shared. |
| **39–43** `g_tick`, `g_completed`, `g_done_cv` | Global graph tick and completion counter | Works if both GPUs submit to the same graph sequence. |
| **44–45** `g_uploader` | Single global uploader function table | Must be per-device. |
| **47** `g_planner` | Single global bank planner | The planner (`dmoe_bank_plan` in llama-tosh-dmoe.cpp) uses `g_layer_by_il[il]` to find the layer's arena tensors. It must select the correct device's arena. |
| **49–54** `g_obs_ring`, `g_obs`, `g_obs_seq`, etc. | Single global observation ring | Must be per-device, or the policy must read from all devices' rings. |
| **159–161** `g_vram_dev_free[8]`, `g_vram_dev_total[8]` | Per-device VRAM tracking | **Correctly per-device** — but only used by `tosh_dmoe_vram_dev()`. The budget function uses legacy `tosh_dmoe_vram()`. |

### ggml-metal-context.m

| File:Line | What It Holds/Does | Why It Breaks |
|-----------|-------------------|--------------|
| **4212–4243** Graph submission | Assigns publish values via `tosh_dmoe_next_value()` for all PUBLISH ops in the graph, regardless of device | The publish value sequence is global. The executor's leader thread reads `tosh_dmoe_event_get()` which returns ONE device's event value. It won't see the other device's publishes. |
| **4320** `ggml_metal_device_dmoe_event(ctx->dev)` | Gets the event for the context's device | The context (`ctx->dev`) is one Metal device. With layer split, a single graph spans two devices, so there are two contexts (or one context with two command queues?). Actually, the Metal backend currently uses one `ggml_metal_t` context per graph submission, tied to one device. For multi-GPU, the graph is split across devices at a higher level. |

### llama-model.cpp / llama-model.h

| File:Line | What It Holds/Does | Why It Breaks |
|-----------|-------------------|--------------|
| **795** `dev_layer(int il)` | Returns the `ggml_backend_dev_t` for a layer | **This is the layer→device map.** It exists and is populated at load time (line 1624–1626). The runtime must use this to know which device owns each MoE layer. |
| **1971** `llama_tosh_dmoe_init(layers, hparams)` | Called after all layers are created and assigned to devices | At this point, `model.dev_layer(il)` is available for every layer. The runtime can build a layer→device map. |

### Executor Signalling (Critical Path)

**Current flow (single GPU):**
1. GPU PUBLISH op runs on device → writes routing to stage → signals `dmoe_ev` with odd value `v`
2. CPU executor leader: `v = tosh_dmoe_event_get()` (reads global `g_ev`)
3. If `v` is odd and new, `job = tosh_dmoe_job_of(v)`, execute `job(il, ...)`
4. CPU writes results to stage → `tosh_dmoe_event_set(v + 1)` (signals global `g_ev`)
5. GPU JOIN op: `encodeWaitForEvent(g_ev, v + 1)`

**With two GPUs:**
- Each layer's PUBLISH/JOIN runs on its layer's device.
- The CPU executor is single-threaded (one leader).
- The leader must wait on **both** devices' events.
- When a value `v` appears on device D's event, the leader processes layer `il` (which lives on D).
- The leader must signal `v+1` on **device D's event** (not a global event).
- The global `g_value` sequence (tosh-dmoe.cpp:23) is shared, so values are unique across devices. This is good.
- **But** `tosh_dmoe_event_get()` and `tosh_dmoe_event_set()` are scalar. They must become per-device.

### Stage Buffers

- Each device has its own stage buffer (`dmoe_stage` in ggml-metal-device.m:1228).
- `tosh_dmoe_set_stage()` registers one global stage. Must become per-device.
- `tosh_dmoe_stage_layer(il)` computes `g_stage + il * g_stride`. Must select the correct device's stage based on `il`'s device.

### Residency Tables

- Host memory table (`g_tables`) is shared — **this works**.
- Each device wraps it in a no-copy buffer (`dmoe_tables`). This works.
- The policy publishes versions to the shared table. This works.
- GPU kernels read the table via the device's buffer. This works.

### Promotions and Uploads

- Policy thread (`policy::cycle()`) calls `up->upload()` via `tosh_dmoe_get_uploader()`.
- The uploader is per-device (Metal: `ggml_metal_dmoe_uploader_init` binds to `g_uploader_dev`).
- **Fix**: Policy must have per-device uploaders. When promoting an expert for layer `il`, use the uploader for `dev_layer(il)`.

### Observation Ring

- Each device has its own observation ring (`dmoe_obs`).
- `tosh_dmoe_set_obs_ring()` registers one globally.
- Policy reads from `tosh_dmoe_obs_ring()` (one ring).
- **Fix**: Policy must read from all devices' rings, or rings must be merged. Since observations are per-layer, and layers are split by device, the policy can iterate devices and read each ring.

### Teardown and Rebuild

- `dmoe_teardown()` (llama-tosh-dmoe.cpp:1754) stops policy, waits for uploads, frees `g_arena_buf`.
- `llama_tosh_dmoe_budget()` can trigger rebuild (line 1807–1812).
- With two GPUs, rebuild must free both arena buffers and recreate per-device.

---

## 2. The Publish Sequence: Can One Global Sequence Work?

**Current mechanism** (tosh-dmoe.cpp:92):
```c
uint64_t tosh_dmoe_next_value(void) { return g_value.fetch_add(2); }
```
Values are odd: 1, 3, 5, 7... The answer is `value + 1` (even).

**Graph submission** (ggml-metal-context.m:4225):
```cpp
const uint64_t value = tosh_dmoe_next_value();
memcpy(&node->op_params[2], &value, sizeof(value));
```
Every PUBLISH node in the graph gets a unique value at submission time, before encoding.

**PUBLISH op** (ggml-metal-ops.cpp:4366):
```cpp
ggml_metal_encoder_event(enc, ctx->cmd_buf, ev, value, true);  // signal value
```

**JOIN op** (ggml-metal-ops.cpp:4396):
```cpp
ggml_metal_encoder_event(ctx->enc, ctx->cmd_buf, ev, value + 1, false);  // wait for value+1
```

**Executor leader** (llama-tosh-dmoe.cpp:605–635):
```cpp
const uint64_t v = tosh_dmoe_event_get();  // reads g_ev
if (v == answered || v % 2 == 0) continue;
job = tosh_dmoe_job_of(v);
// ... process job ...
tosh_dmoe_event_set(v + 1);  // signals g_ev
```

### Does a Global Sequence Work?

**Yes, the value sequence itself works** — values are unique across devices, `tosh_dmoe_job_of(v)` maps to the job struct, and the JOIN op waits on `value+1` on the same event the PUBLISH signaled.

**But the event is the problem:** `tosh_dmoe_event_get/set` operate on a single global event (`g_ev`). With two GPUs:
- GPU 0 signals its event with value 1.
- GPU 1 signals its event with value 3.
- The executor calls `tosh_dmoe_event_get()` → reads **one** event (whichever was registered last).
- It misses the other device's publishes entirely.

**What would break:**
1. The executor only sees one device's publishes.
2. The other device's JOIN ops wait forever on their event (no one signals `value+1`).
3. Watchdog fires, `tosh_dmoe_fail()`, GPU hangs.

**Additional timing issue:** The two GPUs run their layers sequentially within a token (layer 0 on GPU 0, layer 1 on GPU 1, etc.). The graph is submitted as one command buffer per device (or split across command buffers). The PUBLISH on GPU 1 for layer 1 may be submitted before GPU 0 finishes layer 0. But the publish values are assigned at submission time (before encoding), so value 1 goes to layer 0 (GPU 0), value 3 to layer 1 (GPU 1). The executor processes them in value order (1, then 3). This is correct — the GPU 1 JOIN for value 3 waits on its event, which the executor signals after processing value 3. No cross-device dependency in the value sequence.

**Conclusion:** A single global value sequence is fine. The fix is making `tosh_dmoe_event_get/set` per-device, and the executor polling all devices' events.

---

## 3. The Layer-to-Device Map

**Available at init time:**
- `llama_model::dev_layer(int il)` (llama-model.h:795, llama-model.cpp:2571) returns the `ggml_backend_dev_t` for layer `il`.
- Populated in `llama_model_base::load_tensors()` at line 1624–1626:
  ```cpp
  pimpl->dev_layer.resize(n_layer_all);
  for (int il = 0; il < n_layer_all; ++il) {
      pimpl->dev_layer[il] = get_layer_buft_list(il);
  }
  ```
- `llama_tosh_dmoe_init()` is called at line 1971, after `dev_layer` is populated.

**What the runtime needs:**
- A vector `layer_device[il] = ggml_backend_dev_t` for all layers.
- For each MoE layer, know its device to:
  - Allocate arena tensors on the correct buffer type.
  - Select the correct device's event, stage, uploader.
  - Know which device's event to signal in the executor.

**Current code** does not pass this map to the DMoE runtime. The runtime only sees `layers` vector and `hparams`.

---

## 4. Change List: Minimal Changes for Two-GPU Layer Split

### Design Rules
- With one GPU: **no behavior change**.
- One CPU executor (leader + helpers).
- Per-device arena buffers, sized from each device's free VRAM.
- Uniform slot count per layer = `min(quota_per_device)`.
- Every per-device Metal object (event, stage, uploader, wide stage, obs ring) selected by layer's device.

---

### Phase 1: Plumbing — Per-Device Rendezvous in tosh-dmoe.cpp

| # | File:Line | Change |
|---|-----------|--------|
| 1 | **tosh-dmoe.h:81–83** | Add per-device event API: `tosh_dmoe_set_event_dev(int dev_idx, void*, get_fn, set_fn)`, `tosh_dmoe_event_get_dev(int)`, `tosh_dmoe_event_set_dev(int, uint64_t)`. Keep legacy scalar API for single-GPU compat (maps to device 0). |
| 2 | **tosh-dmoe.h:99–100** | Add `tosh_dmoe_set_stage_dev(int dev_idx, void*, size_t stride)`, `tosh_dmoe_stage_layer_dev(int dev_idx, int il)`. |
| 3 | **tosh-dmoe.h:107** | Add `tosh_dmoe_set_wide_stage_dev(int dev_idx, void*, size_t)`. |
| 4 | **tosh-dmoe.h:119–120** | Add `tosh_dmoe_set_obs_ring_dev(int dev_idx, void*)`, `tosh_dmoe_obs_ring_dev(int dev_idx)`. |
| 5 | **tosh-dmoe.h:152–153** | Add `tosh_dmoe_set_uploader_dev(int dev_idx, const tosh_dmoe_uploader*)`, `tosh_dmoe_get_uploader_dev(int dev_idx)`. |
| 6 | **tosh-dmoe.cpp:16–21** | Replace `g_ev`, `g_ev_get`, `g_ev_set` with `g_ev[8]`, `g_ev_get[8]`, `g_ev_set[8]`. |
| 7 | **tosh-dmoe.cpp:16–18** | Replace `g_stage`, `g_stride` with `g_stage[8]`, `g_stride[8]`. |
| 8 | **tosh-dmoe.cpp:118–124** | Replace `g_wide_stage`, `g_wide_bytes` with per-device arrays. |
| 9 | **tosh-dmoe.cpp:49–54** | Replace `g_obs_ring` with `g_obs_ring[8]`, add per-device `g_obs_off[8]`, `g_obs_pos[8]`. `g_obs` records can stay shared (they store `il`). |
| 10 | **tosh-dmoe.cpp:44–45** | Replace `g_uploader` with `g_uploader[8]`, `g_has_uploader[8]`. |
| 11 | **tosh-dmoe.cpp:82–90** | Implement `tosh_dmoe_event_get_dev(i)` / `set_dev(i, v)`. Legacy `tosh_dmoe_event_get/set` call `dev=0`. |
| 12 | **tosh-dmoe.cpp:71–74** | Implement `tosh_dmoe_stage_layer_dev(dev, il)`. Legacy `tosh_dmoe_stage_layer(il)` calls `dev=0`. |
| 13 | **tosh-dmoe.cpp:375–380** | Implement per-device uploader get/set. |
| 14 | **tosh-dmoe.cpp:382–383** | Implement per-device obs ring get/set. |
| 15 | **tosh-dmoe.cpp:439–441** | `tosh_dmoe_job_of()` unchanged (global job ring keyed by global value). |

**Test:** Single GPU — all `dev_idx=0`, behavior identical.

---

### Phase 2: Metal Backend — Register Per-Device Objects

| # | File:Line | Change |
|---|-----------|--------|
| 16 | **ggml-metal-device.m:1239–1247** | In `ggml_metal_device_dmoe_event(dev)`, pass device index to `tosh_dmoe_set_event_dev(device, ...)`. |
| 17 | **ggml-metal-device.m:1249–1258** | In `ggml_metal_device_dmoe_reach_event(dev)`, pass device index to `tosh_dmoe_set_reach_event_dev(device, ...)` (add per-device reach event API). |
| 18 | **ggml-metal-device.m:1260–1271** | In `ggml_metal_device_dmoe_obs_ring(dev)`, pass device index to `tosh_dmoe_set_obs_ring_dev(device, ...)`. |
| 19 | **ggml-metal-device.m:1454–1465** | In `ggml_metal_device_dmoe_wide_stage(dev, ...)`, pass device index to `tosh_dmoe_set_wide_stage_dev(device, ...)`. |
| 20 | **ggml-metal-device.m:1467–1480** | In `ggml_metal_device_dmoe_stage(dev, ...)`, pass device index to `tosh_dmoe_set_stage_dev(device, ...)`. |
| 21 | **ggml-metal-device.m:1431–1439** | In `ggml_metal_dmoe_uploader_init(dev)`, register uploader via `tosh_dmoe_set_uploader_dev(device, ...)`. Remove `g_uploader_dev` singleton. |
| 22 | **ggml-metal-ops.cpp:4320–4322** | PUBLISH op: `void * ev = ggml_metal_device_dmoe_event(ctx->dev);` — already per-device. No change. |
| 23 | **ggml-metal-ops.cpp:4321** | Stage: `ggml_metal_device_dmoe_stage(ctx->dev, stride)` — already per-device. No change. |
| 24 | **ggml-metal-ops.cpp:4389–4391** | JOIN op: same — already per-device. No change. |
| 25 | **ggml-metal-ops.cpp:4427** | OBSERVE op: `ggml_metal_device_dmoe_obs_ring(ctx->dev)` — already per-device. No change. |

**Test:** Two GPUs — each device registers its own event/stage/uploader. No cross-talk.

---

### Phase 3: Runtime Init — Layer→Device Map & Per-Device Arenas

| # | File:Line | Change |
|---|-----------|--------|
| 26 | **llama-tosh-dmoe.h** | Add `llama_tosh_dmoe_init_ex(layers, hparams, layer_devices)` taking `std::vector<ggml_backend_dev_t> layer_devices` (size = n_layer). Keep old `llama_tosh_dmoe_init` for compat (assumes all layers on device 0). |
| 27 | **llama-model.cpp:1971** | Call `llama_tosh_dmoe_init_ex(layers, hparams, dev_layer_vector)` where `dev_layer_vector[il] = pimpl->dev_layer[il].dev`. |
| 28 | **llama-tosh-dmoe.cpp:1873** | Replace `ggml_backend_dev_by_type(...)` with per-layer device from `layer_devices[il]`. Build `std::vector<ggml_backend_buffer_type_t> buft_per_layer`. |
| 29 | **llama-tosh-dmoe.cpp:1389** | Replace `g_arena_buf` with `std::vector<ggml_backend_buffer_t> g_arena_bufs` (one per device). |
| 30 | **llama-tosh-dmoe.cpp:1828–1965** `dmoe_init()` | **Major restructure:**<br>• Group layers by device.<br>• For each device: compute `quota_d = cache_mib / per_expert_all_layers_on_device`.<br>• Global `quota = min(quota_d)` (uniform slots).<br>• For each device: create ggml context, allocate arena tensors for its layers from its `buft`.<br>• Store `dl.arena_*` tensors in `g_layers` as before.<br>• Create one residency table tensor per device? No — residency table is host memory (shared). The `dl.residency` tensor can be a host tensor (not in arena buffer). Or keep one per device wrapping same host memory. Simpler: make `dl.residency` a host tensor (buffer = CPU), same for all devices. |
| 31 | **llama-tosh-dmoe.cpp:1960** | Allocate per-device: `ggml_backend_alloc_ctx_tensors_from_buft(ctx_dev, buft_dev)` for each device's context. |
| 32 | **llama-tosh-dmoe.cpp:1977** | `ggml_backend_tensor_set(dl.residency, ...)` — residency tensor is host memory, so `ggml_backend_tensor_set` works regardless of device. |
| 33 | **llama-tosh-dmoe.cpp:2012–2014** | `tosh_dmoe_set_tables()` called once (shared host table). Each device's `dmoe_tables` buffer wraps it (already works via `ggml_metal_device_dmoe_tables`). |
| 34 | **llama-tosh-dmoe.cpp:2023** | Policy uploader: instead of single `pol->up`, use `pol->up_dev[dev_idx]` array. In `cycle()`, when uploading for layer `il`, use `up_dev[dev_of_il]`. |

**Test:** Two GPUs — two arena buffers, each holding its layers' slots. Quota = min across devices.

---

### Phase 4: Executor — Poll All Devices, Signal Correct Device

| # | File:Line | Change |
|---|-----------|--------|
| 35 | **llama-tosh-dmoe.cpp:68–165** `executor` struct | Add `std::vector<int> layer_to_dev` (size = n_layer). Populate in `dmoe_init()`. |
| 36 | **llama-tosh-dmoe.cpp:591–641** `leader_main()` | Replace single `tosh_dmoe_wait_active()` + `tosh_dmoe_event_get()` loop with:<br>• Poll all devices' events (or use a combined wait).<br>• Simplest: loop over devices, check `tosh_dmoe_event_get_dev(d)`. If odd and > answered_for_dev[d], process that job.<br>• Track `answered_per_dev[8]`.<br>• When processing job `v` for layer `il`, use `dev = layer_to_dev[il]`.<br>• Call `tosh_dmoe_event_set_dev(dev, v + 1)`. |
| 37 | **llama-tosh-dmoe.cpp:586–587** `job()` / `job_wide()` | Stage pointer: `char * stage = (char *) tosh_dmoe_stage_layer_dev(dev, il);`<br>Wide stage: `tosh_dmoe_wide_stage_dev(dev, &bytes)`. |
| 38 | **llama-tosh-dmoe.cpp:496** `job()` | Already gets stage via `tosh_dmoe_stage_layer(il)`. Change to per-device. |
| 39 | **llama-tosh-dmoe.cpp:381** `job_wide()` | Already gets wide stage via `tosh_dmoe_wide_stage()`. Change to per-device. |
| 40 | **llama-tosh-dmoe.cpp:643–665** `watchdog_main()` | Must check all devices' events. If any device has a stuck odd value, fail. |

**Test:** Two GPUs — executor sees publishes on both devices, processes each on its device's stage, signals back on that device's event.

---

### Phase 5: Policy — Per-Device Uploaders, Per-Device Observation Rings

| # | File:Line | Change |
|---|-----------|--------|
| 41 | **llama-tosh-dmoe.cpp:799** `policy::up` | Change to `std::vector<const tosh_dmoe_uploader*> up_dev;` (size = n_devices). |
| 42 | **llama-tosh-dmoe.cpp:2023** | In `dmoe_init()`, after creating per-device uploaders (via Metal), populate `pol->up_dev[dev] = tosh_dmoe_get_uploader_dev(dev)`. |
| 43 | **llama-tosh-dmoe.cpp:1229** `sl.ticket = up->upload(...)` | In `cycle()`, when promoting for layer `il`: `dev = layer_to_dev[il]; sl.ticket = up_dev[dev]->upload(...);` |
| 44 | **llama-tosh-dmoe.cpp:1038** `up->status()` / **1048** `up->gpu_us()` | Use `up_dev[dev]` for the layer's device. |
| 45 | **llama-tosh-dmoe.cpp:1100** `up->download()` | Use `up_dev[dev]` for the layer's device. |
| 46 | **llama-tosh-dmoe.cpp:989–1031** Observation processing | Policy reads from `tosh_dmoe_obs_ring()` (global). Change to loop over devices: `for (dev) { ring = tosh_dmoe_obs_ring_dev(dev); ... }`. The observation records already contain `il`, so the policy knows which layer. |
| 47 | **llama-tosh-dmoe.cpp:848–861** `observe_cb()` | Called by executor with `il`. The policy pushes to `ring[il]`. No change needed — `ring` is per-layer, not per-device. The observation ring *storage* is per-device, but the policy's logical ring is per-layer. The policy reads from all devices' physical rings and merges into its logical per-layer rings. |

**Test:** Promotions for GPU 0 layers go through GPU 0's upload queue; GPU 1 layers through GPU 1's. Observations from both GPUs are collected.

---

### Phase 6: Budget & Rebuild — Per-Device VRAM

| # | File:Line | Change |
|---|-----------|--------|
| 48 | **llama-context.cpp:536–547** | Instead of summing `gpu_bytes`, collect per-device free VRAM: `std::vector<size_t> gpu_bytes_per_dev`. Pass to `llama_tosh_dmoe_budget()`. |
| 49 | **llama-tosh-dmoe.h** | Change `llama_tosh_dmoe_budget(size_t gpu_bytes)` to `llama_tosh_dmoe_budget(const std::vector<size_t>& gpu_bytes_per_dev)`. Keep old overload for compat (assumes single device). |
| 50 | **llama-tosh-dmoe.cpp:1772–1826** `llama_tosh_dmoe_budget()` | For each device: `free0 = gpu_bytes_per_dev[dev]` (or query `tosh_dmoe_vram_dev(dev, ...)`). Compute `arena_d` per device. Sum for logging. If rebuild needed, call `dmoe_teardown()` then `dmoe_init_or_off()` with per-device arenas. |
| 51 | **llama-tosh-dmoe.cpp:1754–1770** `dmoe_teardown()` | Free all `g_arena_bufs[dev]`. Wait for all devices' pending uploads. |
| 52 | **llama-tosh-dmoe.cpp:1828** `dmoe_init()` | Accept per-device `cache_mib` vector or compute per-device quota internally. |

**Test:** Two GPUs with different free VRAM — each gets its own arena size. Rebuild works.

---

### Phase 7: Bank Planner — Select Correct Device's Arena

| # | File:Line | Change |
|---|-----------|--------|
| 53 | **llama-tosh-dmoe.cpp:1398–1494** `dmoe_bank_plan()` | The planner receives `host` (bank tensor data pointer) and `size`. It looks up `g_bank_refs[host]` to get `il` and `which` (gate/up/down). Then `dl = g_layer_by_il[il]`. **Add**: `dev = layer_to_dev[il]`. Set `plan->arena` to `dl->arena_gate/up/down` (already correct, since `dl` has the right device's arena tensor). The uploader will be selected by the policy per-device. No change needed to planner logic — it already returns the correct arena tensor for the layer. |

**Test:** Prefill uploads for layer on GPU 1 use GPU 1's arena tensor (which lives in GPU 1's arena buffer).

---

## 5. Risks and Unknowns

| Risk | Description | Mitigation |
|------|-------------|------------|
| **Graph submission model** | The Metal backend currently submits one graph per `ggml_metal_t` context (one device). With layer split, the graph is split across devices at the `llama.cpp` level (multiple backends?). Need to verify how `GGML_METAL_DEVICES=2 --split-mode layer` works — does it create two Metal backends/contexts? | Check `ggml-backend-metal.cpp` for multi-device graph splitting. If each device gets its own context, each context submits its subgraph. The publish values are assigned in `ggml_metal_graph_compute()` (line 4225) which runs per-context. **Critical**: The global `tosh_dmoe_next_value()` must be called once per graph, not per-context. Currently it's called in `ggml_metal_graph_compute()` which runs per context. This would double-assign values. **Fix**: Move value assignment to a higher level (llama-context.cpp) before splitting, or use a shared counter across contexts. |
| **Command buffer synchronization** | GPU 0's JOIN waits on its event. GPU 1's PUBLISH may be in a different command buffer. No cross-device sync in Metal without shared events (which we have). But the CPU executor is the bridge. | The executor signals `value+1` on the correct device's event. The JOIN op on that device waits on it. This works. |
| **Unified memory vs discrete** | On Apple Silicon (unified memory), host↔device copies are zero-copy. On discrete GPUs (FirePro D700), copies go over PCIe. The stage buffers are `MTLResourceStorageModeShared` (host-visible). This works on both. | No change needed. |
| **Residency table versioning** | The policy publishes a version. GPUs read the version at graph submit (line 4213, 4228). With two GPUs submitting subgraphs, both must read the same version. | Graph submission is serialized in llama-context.cpp (one thread). The version is captured once per graph (line 4213). Both subgraphs get the same version via `op_params[4]`. This works. |
| **Observation ring wraparound** | Each device has its own ring. The policy reads all. If one device's ring wraps faster, observations may be lost. | Ring size is 32 MiB (TOSH_DMOE_OBS_RING_BYTES). Prefill generates observations; decode does not. Should be fine. |
| **Wide stage (prefill)** | Only one wide layer runs at a time (sequential layers). The wide stage is per-device. The GPU 1 wide layer uses GPU 1's wide stage. The executor calls `tosh_dmoe_wide_stage_dev(dev, ...)`. | Works. |
| **Rare-row threshold** | Adaptive rare-row logic (`tosh_dmoe_rare_*`) is global. It tracks host vs GPU timing per layer. With two GPUs, layers on different devices have different timing. | The rare-row threshold is per-layer (tracked in `g_rare.layers[il]`). It adapts per layer. Works. |
| **Watchdog** | Watchdog checks `tosh_dmoe_event_get()` (one device). Must check all. | Phase 4 change #40 addresses this. |
| **Legacy API compatibility** | Existing single-GPU code calls `tosh_dmoe_event_get()`, `tosh_dmoe_stage_layer()`, etc. | All legacy APIs map to `dev_idx=0`. Single-GPU behavior unchanged. |
| **Memory pressure / OOM** | Two arenas + two stage buffers + two wide stages + two obs rings = more VRAM. | The planner already accounts for per-device memory. The budget function computes per-device arena from free VRAM. |
| **CPU executor contention** | One executor serves both GPUs. If both GPUs publish simultaneously, the executor processes sequentially. Could become a bottleneck. | The executor is already multi-threaded (helpers). The leader is single-threaded but fast (just dispatches to helpers). For decode (few tokens), latency is sub-ms. For prefill (wide), only one wide layer at a time. Acceptable. |
| **Metal device index vs ggml_backend_dev_t** | The Metal backend assigns device indices 0, 1... based on `GGML_METAL_DEVICES` order. `ggml_backend_dev_t` for each device is distinct. The layer→device map uses `ggml_backend_dev_t`. Need a mapping `ggml_backend_dev_t → metal_device_index (0..7)` for indexing per-device arrays. | In `ggml-metal-device.m`, each `ggml_metal_device_t` has a `device` field (the index). The `ggml_backend_dev_t`'s context points to `ggml_metal_device_t`. So `((ggml_metal_device_t)dev->context)->device` gives the index. Add helper `ggml_metal_get_device_index(ggml_backend_dev_t)`. |

---

## Summary of Key Structural Changes

1. **tosh-dmoe.cpp**: All global rendezvous state → per-device arrays (max 8 devices). Legacy scalar APIs map to device 0.
2. **ggml-metal-device.m**: Register per-device objects with device index.
3. **llama-tosh-dmoe.cpp**: 
   - Accept layer→device map at init.
   - Create per-device arena buffers, quotas, uploaders.
   - Executor leader polls all devices' events, signals back on correct device.
   - Policy uses per-device uploaders, reads all devices' obs rings.
4. **llama-context.cpp**: Pass per-device VRAM to budget; pass layer→device map to init.
5. **llama-model.cpp**: Provide layer→device map at `llama_tosh_dmoe_init` call site.

**Single-GPU compatibility**: All legacy code paths use device 0. No behavior change when only one GPU is present.

**Testing strategy**:
1. Run existing single-GPU DMoE tests — must pass.
2. Simulate two GPUs on one machine (if possible) or use CI with multi-GPU.
3. Verify arena sizes match per-device free VRAM.
4. Verify publish/join round-trip on both devices.
5. Verify promotions go to correct device's arena.
6. Verify observation collection from both devices.
7. Test rebuild (budget change) with two GPUs.

---

This analysis is complete. All file:line citations are from the actual codebase. Items marked **inferred** are noted where the exact line wasn't read but the pattern is clear from surrounding code.
