# 02 — Timestep correct fix as patch 0114

Status: resolved
Type: task
Blocked by: 01 (resolved)

## Question

What is the minimal kernel fix that turns the red loop green without regressing bench numbers, landed per patch rules?

## Answer

### Root cause

GCN/Tahiti miscompiles the integer parity test `args.dim % 2 != 0` in
`kernel_timestep_embedding_f32`. For an even `dim` (320) it takes the odd-dim branch
anyway. That branch writes `embed_data[2 * half_]`, and with `half_ = dim/2 = 160` that
index is **one full row past** the row this threadgroup owns:

- Row 0's branch zeroes element 320 = row 1's first element
- Row 1's branch zeroes element 320 = one past the end of `dst`

So every row zeroed its successor's first element, and the last row wrote out of bounds.
That is the sentinel mismatch, and it is the numeric error too.

### How it was found

Ticket 01's red loop plus a byte-level probe (temporary prints in `test-backend-ops.cpp`,
since reverted and verified byte-identical to the original):

```
[PROBE TIMESTEP_EMBEDDING n=640 first=320 last=320 gpu=0.000000 cpu=0.987142]
[PROBE sent=sent_2 ndiff=1/1024 first=0 last=0 gpu=0.000000 cpu=0.113454]
```

Exactly one float wrong in `out`, always at index 320, always `0.0`. Exactly one float
wrong in `sent_2`, always index 0, always `0.0`. Both are the same write seen from two
angles. The non-determinism in ERR (1.0e-3 … 3.1e-3) was never kernel arithmetic: the input
`a` is re-randomized every run, so the *correct* value at index 320 moves each time while the
*wrong* value stays pinned at 0.

Confirmed by shape change: with `ne_a=[4,1,1,1], dim=256` the probe moved to indices
256, 512 and 768 — one per row boundary, i.e. exactly `nb1` apart. That is the signature of a
row-stride-past write, not a numeric defect.

Confirmed by armed write: forcing the branch to fire with a sentinel value
(`embed_data[2*half_] = 12345.0f`) reproduced the same positions with that value.
Disabling the branch entirely turned the test green.

Also refuted along the way: write-combined host staging (`TOSH_STAGE_WC_OFF=1` — still
fails, three runs), and the discarded `precise::` patch (ticket 01).

### The fix

`patches/llama/0114-metal-timestep-embedding-gcn-parity.patch` — one hunk, kernel-local:

```metal
-    if (args.dim % 2 != 0 && tpitg.x == 0) {
+    if (half_ * 2 < args.dim && tpitg.x == 0) {
         embed_data[2 * half_] = 0.f;
     }
```

Same predicate (is the row length odd), expressed as an int multiply-compare that GCN
compiles correctly. Number 0114 reused, as reserved by grilling Q4; the discarded
`precise::` content is recorded below and stays deleted.

### Validation

- Red loop: `test-backend-ops -b MTL0 -o TIMESTEP_EMBEDDING` → `1/1 tests passed`, `3/3 backends passed`.
- Stability: 4 consecutive runs green, no drift.
- Full `test-backend-ops -b MTL0`: the only failure in the suite before the fix was this op; after the fix the suite runs clean.
- **Gate applied: kernel-local** (Q2). Only `kernel_timestep_embedding_f32`'s own body changed, so the LLM text path cannot regress by construction — `timestep_embedding` is diffusion/image only. No pp/tg baseline owed.

### The discarded precise:: patch

Deleted at grilling Q4. Content preserved for the record; it did not fix the failure because
the failure was never precision.

```
-        float freq = (float)exp(-log((float)args.max_period) * j / half_);
+        float freq = (float)precise::exp(-precise::log((float)args.max_period) * j / half_);
-        embed_data[j        ] = cos(arg);
-        embed_data[j + half_] = sin(arg);
+        embed_data[j        ] = precise::cos(arg);
+        embed_data[j + half_] = precise::sin(arg);
```

## Comments

- 2026-10-01: resolved. GCN codegen bug, row-stride-past write. Patch 0114, kernel-local, full suite clean.
