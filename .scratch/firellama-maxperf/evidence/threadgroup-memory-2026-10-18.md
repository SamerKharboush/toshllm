# Ticket 35: the dk128 threadgroup (LDS) memory request, measured on the FirePro D700

Ticket: `../issues/35-run-the-probe-on-d700.md`. Spec: `../spec.md` (Revisions section, which
supersedes the body). Probe: `tools/metal-probe/threadgroupprobe.m` at `b6eb6ed`
(sha256 `267f6ad6d1c7e3720acada94b812542404cf9aab7e339e2b3261a072e8405cc1`).
Date: 2026-10-18. Scope: measurement only. No source file, patch, or tool was modified.

## Answer

`device_max_threadgroup_memory_length_bytes = 32768` on both devices.

| function (`kernel_flash_attn_ext_vec_amd_` + suffix) | device 0 | device 1 |
|---|---|---|
| `dk40_kf16_vf16_w64`            | built, 23552 bytes, exceeds NO   | not run |
| `dk64_kf16_vf16_w64`            | REFUSED, unavailable, UNKNOWN    | not run |
| `dk64_kf16_vf16_w64_lds32`      | built, 17920 bytes, exceeds NO   | built, 17920 bytes, NO |
| `dk64_kf16_vf16_w64_wg32_lds32` | built, 17920 bytes, exceeds NO   | not run |
| `dk72_kf16_vf16_w64`            | built, 19968 bytes, exceeds NO   | not run |
| `dk80_kf16_vf16_w64`            | built, 22016 bytes, exceeds NO   | not run |
| `dk128_kf16_vf16_w64`           | REFUSED, unavailable, UNKNOWN (x3) | REFUSED, unavailable, UNKNOWN |
| `dk128_kf16_vf16_w64_lds32`     | built, **17152 bytes**, exceeds **NO** (x3) | built, **17152 bytes**, exceeds **NO** (x2) |
| `dk128_kf16_vf16_w64_wg32`      | REFUSED, unavailable, UNKNOWN    | not run |
| `dk128_kf16_vf16_w64_wg32_lds32`| built, 17152 bytes, exceeds NO   | built, 17152 bytes, NO |
| `dk160_kf16_vf16_w64`           | built, 10624 bytes, exceeds NO   | not run |
| `dk256_kf16_vf16_w64`           | REFUSED, unavailable, UNKNOWN    | not run |
| `dk256_kf16_vf16_w64_lds32`     | built, 16768 bytes, exceeds NO   | built, 16768 bytes, NO |
| `dk256_kf16_vf16_w64_wg32_lds32`| built, 16768 bytes, exceeds NO   | not run |
| `dk512_kf16_vf16_w64`           | REFUSED, unavailable, UNKNOWN    | not run |
| `dk512_kf16_vf16_w64_lds32`     | built, 16576 bytes, exceeds NO   | not run |

Every built request is `MTLComputePipelineState.staticThreadgroupMemoryLength` plus the sum of
`MTLThreadgroupBinding.threadgroupMemoryDataSize`; the binding sum was 0 in all 18 runs that
built, so each number above is the pipeline's own static allocation. No measured request exceeds 32768;
the largest that builds is 23552, which is 9216 bytes below the ceiling.

The plain `dk128` request **cannot be obtained**, and is recorded as unobtainable rather than as a
failed run. Metal exposes a pipeline's threadgroup bytes only through a pipeline state that was
built, and this pipeline has no state. The probe prints `unavailable` /
`refused_pipeline_has_no_state` for it and exits 3, which is the probe's refusal exit code, not a
probe error (a probe error is exit 2).

## The finding that matters

A variant of the same kernel, on the same K/V types and the same wave64 width, **builds at 17152
bytes**, 15616 bytes under the 32768 ceiling. So the open question is not "reduce the threadgroup
memory": a working variant is already within budget. The question is why the kernel selector's
first request is a name that does not build, and what runs in its place.

The measurement also declines to blame the byte count. The set of plain widths that refuse is
`{64, 128, 256, 512}` (`dk128` also refuses as `_wg32`). The set of plain widths that build is
`{40, 72, 80, 160}`. Those two sets are exactly the widths that have an `_lds32` twin in
`fa.metallib` and the widths that do not. Width, not measured size, separates them: plain `dk40`
builds at 23552 bytes while plain `dk128` refuses with an unmeasurable request. Two readings are
consistent with this and the data does not choose between them: either the twin exists because
the plain form of those widths overflows (and the refusal is a truthful memory report), or the
refused names never had a viable layout and the twin is the only real instantiation. Nothing here
excludes a byte-count explanation for the plain `dk128`; it only shows that a larger measured
request builds.

No layout tweak follows from this record, and none is proposed. The layout of the working variant
is already inside the 32768-byte budget.

## Method line

- Machine: `Sams-Mac-Pro`, Intel Mac Pro, x86_64. Two AMD `AMD Radeon HD - FirePro D700`, reported
  by `MTLCopyAllDevices` as indices 0 and 1; both report
  `device_max_threadgroup_memory_length_bytes=32768`.
- macOS 15.8, build 24H23, Darwin 24.6.0.
- Compiler: Apple clang version 17.0.0 (clang-1700.6.4.2), target x86_64-apple-darwin24.6.0.
- Build:
  `clang -fobjc-arc -framework Foundation -framework Metal -o /tmp/ldsprobe/threadgroupprobe tools/metal-probe/threadgroupprobe.m`
- Metallib: `vendor/llama.cpp/build-static/bin/kernels/fa.metallib`, 14692576 bytes, mtime
  2026-10-15 21:51, sha256 `af4b13d4ec0f6c7ab9e214d62bb8e9f56417e90e5b9bde5b4cb84efcef0bfe9e`.
  The `_lds32` twins live in this library; `fa_w64.metallib` carries 1124 flash-attention
  function-name strings but none containing `_vec_amd`, so the AMD vec kernels are here only.
- Environment for every run, exported (the probe can hang without them):
  `GGML_METAL_DEVICES=2`, `GGML_METAL_VRAM_RESERVE_MB=1024`,
  `GGML_METAL_SIMDGROUP_REDUCTION_DISABLE=1`.
- Invocation: `perl -e 'alarm 180; exec @ARGV' -- ./threadgroupprobe <device> <metallib> <function>`,
  exit 0 built, 3 refused, 2 probe error. Every run finished in about 0.5 s; no run hit the alarm.
- N: 26 runs. `dk128 plain` 3x on device 0 and 1x on device 1; `dk128_lds32` 3x on device 0 and
  2x on device 1; 1x each for the remaining 17 runs (device, variant) pairs.
- Warmups: none taken and none discarded. The reported quantity is a byte count read at pipeline
  creation, not a duration, and repeats were byte-identical (`cmp` clean on all repeats), so there
  is no warmup policy to state. Wall clock is not a measurement here.
- What could not be run: the plain `dk128`, `dk64`, `dk256`, `dk512` and `dk128_wg32` requests. A
  refused pipeline has no state, so their byte counts are unobtainable on Metal 15.8 by design.

## Runs

Repeat tags (`*_r2`, `*_r3`) were compared with `cmp` and are byte-identical to their base run;
sha256 prefixes below are equal for each such group. `d0` and `d1` outputs differ only in the
`device_index` line.

| run | device | function | exit | sha256 (first 16) |
|---|---|---|---|---|
| d0_dk128_plain            | 0 | dk128 plain            | 3 | c6bd02544bbd1eb9 |
| d0_dk128_plain_r2         | 0 | dk128 plain            | 3 | c6bd02544bbd1eb9 |
| d0_dk128_plain_r3         | 0 | dk128 plain            | 3 | c6bd02544bbd1eb9 |
| d0_dk128_lds32            | 0 | dk128 lds32            | 0 | 6d475621698c4d13 |
| d0_dk128_lds32_r2         | 0 | dk128 lds32            | 0 | 6d475621698c4d13 |
| d0_dk128_lds32_r3         | 0 | dk128 lds32            | 0 | 6d475621698c4d13 |
| d0_dk128_wg32_plain       | 0 | dk128 wg32 plain       | 3 | 2ed584aa5d5595c3 |
| d0_dk128_wg32_lds32       | 0 | dk128 wg32 lds32       | 0 | a3789c5eb6e7b43c |
| d0_dk64_plain             | 0 | dk64 plain             | 3 | c70cc9429ff20f06 |
| d0_dk64_lds32             | 0 | dk64 lds32             | 0 | 3f0428ddc8815d6a |
| d0_dk64_wg32_lds32        | 0 | dk64 wg32 lds32        | 0 | d79dde35a980f87d |
| d0_dk256_plain            | 0 | dk256 plain            | 3 | 93f3963dee22b413 |
| d0_dk256_lds32            | 0 | dk256 lds32            | 0 | 82bbcba6b9659a76 |
| d0_dk256_wg32_lds32       | 0 | dk256 wg32 lds32       | 0 | 71d8b4d731f74d19 |
| d0_dk512_plain            | 0 | dk512 plain            | 3 | c90baaff3c838b70 |
| d0_dk512_lds32            | 0 | dk512 lds32            | 0 | b5d057c8a533e647 |
| d0_dk40_plain             | 0 | dk40 plain             | 0 | a7bb6c717b1fa67c |
| d0_dk72_plain             | 0 | dk72 plain             | 0 | cd8df75b7a614fa2 |
| d0_dk80_plain             | 0 | dk80 plain             | 0 | 7e2862dcbb629973 |
| d0_dk160_plain            | 0 | dk160 plain            | 0 | 635c8e179bc663ea |
| d1_dk128_plain            | 1 | dk128 plain            | 3 | e243984915c3cd44 |
| d1_dk128_lds32            | 1 | dk128 lds32            | 0 | d48b42ea9cf6991f |
| d1_dk128_lds32_r2         | 1 | dk128 lds32            | 0 | d48b42ea9cf6991f |
| d1_dk128_wg32_lds32       | 1 | dk128 wg32 lds32       | 0 | 2b563120cf586a9b |
| d1_dk64_lds32             | 1 | dk64 lds32             | 0 | 23872522190567d0 |
| d1_dk256_lds32            | 1 | dk256 lds32            | 0 | e916acf1574fcf4f |

## The driver error string, verbatim

Refused on every attempt, device 0 and device 1, `dk64`/`dk128`/`dk256`/`dk512` and `dk128_wg32`
alike, `driver_error_domain=CompilerError`, `driver_error_code=2`:

```
driver_error_line[0]=Error Domain=CompilerError Code=2 "
driver_error_line[1]=Linking two modules of different data layouts: '' is '' whereas '1' is 'e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v24:32:32-v32:32:32-v48:64:64-v64:64:64-v96:128:128-v128:128:128-v192:256:256-v256:256:256-v512:512:512-v1024:1024:1024-n8:16:32'
driver_error_line[2]=SC compilation failure
driver_error_line[3]=GPGPU, exceed the local data storage limit" UserInfo={NSLocalizedDescription=
```

Three concatenated messages, not one: a module data-layout mismatch, `SC compilation failure`, and
`GPGPU, exceed the local data storage limit`. The last of the three is the only one about memory,
and it is the one that satisfies the probe's substring test
`driver_says_exceed_local_data_storage_limit=YES`. It is a driver message from
`Error Domain=CompilerError Code=2`. It is not Apple's wording and is not called that here; Metal
words the same condition as "Threadgroup memory size (N) exceeds the maximum threadgroup memory
allowed (M)". The `[err description]` rendering echoes the three messages a second time inside its
`UserInfo` text, which is why the probe splits them into numbered lines instead of escaping them.

The engine's own log of the same refusal (`.scratch/firellama-maxperf/issues/16-...md`) carries the
same three messages for the same base name `kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64`,
which is the name this probe requests. The engine path calls
`newComputePipelineStateWithFunction:error:` without a reflection option, so the data-layout line
is not an artifact of the probe's `MTLPipelineOptionBindingInfo` request.

## Lead, not a measurement: what the selector asks for (read only, no run)

Read from the patched tree, no code changed, no engine run performed. Line numbers are
`vendor/llama.cpp/ggml/src/ggml-metal/ggml-metal-ops.cpp` at the current checkout.

- The name is constructed once, at 4983, as
  `kernel_flash_attn_ext_vec_amd_dk%d_k%s_v%s` plus `_w64` when `props_dev->simd_width == 64`.
  That is the **plain** name. No `_lds32` appears in the construction site.
- The dispatch selector requests that plain name first, at 5323 (which becomes `<name>_wg32` when
  `fa_amd_nwg > 1`, built at 5286).
- Only when that build fails, or when `TOSH_FA_AMD_LDS32` is set, does 5326-5333 request
  `<name>_lds32` and, on success, halve `fa_amd_nsg`. The guard requires `simd_width == 64`, which
  is this hardware's width.
- So the selector does pick a variant that does not build - once, as its first request - and the
  code at 5326 carries a fallback to the twin for exactly that case. This is a candidate answer to
  ticket 16's open question, "what ran in its place": the same kernel's `_lds32` twin, at half the
  simdgroups, not a generic or CPU kernel.
- The failure is paid once per process, not per layer or per token:
  `ggml_metal_fa_amd_pipeline` at 4529 memoises refused names in a static set and short-circuits
  later requests for the same name. The `ggml_metal_library_compile_pipeline` call emits the
  `failed to create pipeline state` line as an error-level log, which is the log line ticket 16
  quoted.

Not established by this read: that the fallback is what actually executes on this machine. That
needs an engine run with pipeline-level logging, which is outside this ticket's scope.

## What this record does not establish

- Nothing here is a runtime measurement of the engine. Every byte count is the driver's answer to
  `newComputePipelineStateWithFunction` at pipeline-creation time.
- The plain `dk128` request remains unknown and unmeasurable on this Metal version, so the record
  cannot say whether that request exceeds 32768.
- Whether the engine lands on `_lds32` at runtime is a code-read inference, flagged above as a lead.
- One device family, one metallib, one OS build. The twin counts are for `kf16_vf16_w64` only; the
  other K/V type pairs and the `dk384`/`dk640` turbo widths were not measured.

## Raw probe output

All 21 distinct (device, variant) pairs, in the order run. Repeat runs are byte-identical to their
base run as recorded in the Runs table above.

### d0_dk128_plain  |  device=0  |  kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64  |  exit=3

```
probe=threadgroup-memory-request
device_count=2
device[0]=AMD Radeon HD - FirePro D700
device[1]=AMD Radeon HD - FirePro D700
device_index=0
device_name=AMD Radeon HD - FirePro D700
device_max_threadgroup_memory_length_bytes=32768
metallib=/Users/sam/firellama/vendor/llama.cpp/build-static/bin/kernels/fa.metallib
function=kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64
metallib_loaded=YES
function_found=YES
pipeline_build=REFUSED
pipeline_static_threadgroup_memory_bytes=unavailable
pipeline_threadgroup_bindings=unavailable
pipeline_dynamic_threadgroup_memory_bytes=unavailable
pipeline_requested_threadgroup_memory_bytes=unavailable
pipeline_requested_threadgroup_memory_source=refused_pipeline_has_no_state
request_exceeds_device_ceiling=UNKNOWN
driver_error_domain=CompilerError
driver_error_code=2
driver_error_line[0]=Error Domain=CompilerError Code=2 "
driver_error_line[1]=Linking two modules of different data layouts: '' is '' whereas '1' is 'e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v24:32:32-v32:32:32-v48:64:64-v64:64:64-v96:128:128-v128:128:128-v192:256:256-v256:256:256-v512:512:512-v1024:1024:1024-n8:16:32'
driver_error_line[2]=SC compilation failure
driver_error_line[3]=GPGPU, exceed the local data storage limit" UserInfo={NSLocalizedDescription=
driver_error_line[4]=Linking two modules of different data layouts: '' is '' whereas '1' is 'e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v24:32:32-v32:32:32-v48:64:64-v64:64:64-v96:128:128-v128:128:128-v192:256:256-v256:256:256-v512:512:512-v1024:1024:1024-n8:16:32'
driver_error_line[5]=SC compilation failure
driver_error_line[6]=GPGPU, exceed the local data storage limit}
driver_error_user_info[NSLocalizedDescription]=
Linking two modules of different data layouts: '' is '' whereas '1' is 'e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v24:32:32-v32:32:32-v48:64:64-v64:64:64-v96:128:128-v128:128:128-v192:256:256-v256:256:256-v512:512:512-v1024:1024:1024-n8:16:32'
SC compilation failure
GPGPU, exceed the local data storage limit
driver_says_exceed_local_data_storage_limit=YES
done
```

### d0_dk128_lds32  |  device=0  |  kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64_lds32  |  exit=0

```
probe=threadgroup-memory-request
device_count=2
device[0]=AMD Radeon HD - FirePro D700
device[1]=AMD Radeon HD - FirePro D700
device_index=0
device_name=AMD Radeon HD - FirePro D700
device_max_threadgroup_memory_length_bytes=32768
metallib=/Users/sam/firellama/vendor/llama.cpp/build-static/bin/kernels/fa.metallib
function=kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64_lds32
metallib_loaded=YES
function_found=YES
pipeline_build=OK
pipeline_static_threadgroup_memory_bytes=17152
pipeline_threadgroup_bindings=0
pipeline_dynamic_threadgroup_memory_bytes=0
pipeline_requested_threadgroup_memory_bytes=17152
pipeline_requested_threadgroup_memory_source=MTLComputePipelineState.staticThreadgroupMemoryLength+MTLThreadgroupBinding.threadgroupMemoryDataSize
request_exceeds_device_ceiling=NO
thread_execution_width=64
max_total_threads_per_threadgroup=512
driver_error=NONE
done
```

### d0_dk128_wg32_plain  |  device=0  |  kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64_wg32  |  exit=3

```
probe=threadgroup-memory-request
device_count=2
device[0]=AMD Radeon HD - FirePro D700
device[1]=AMD Radeon HD - FirePro D700
device_index=0
device_name=AMD Radeon HD - FirePro D700
device_max_threadgroup_memory_length_bytes=32768
metallib=/Users/sam/firellama/vendor/llama.cpp/build-static/bin/kernels/fa.metallib
function=kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64_wg32
metallib_loaded=YES
function_found=YES
pipeline_build=REFUSED
pipeline_static_threadgroup_memory_bytes=unavailable
pipeline_threadgroup_bindings=unavailable
pipeline_dynamic_threadgroup_memory_bytes=unavailable
pipeline_requested_threadgroup_memory_bytes=unavailable
pipeline_requested_threadgroup_memory_source=refused_pipeline_has_no_state
request_exceeds_device_ceiling=UNKNOWN
driver_error_domain=CompilerError
driver_error_code=2
driver_error_line[0]=Error Domain=CompilerError Code=2 "
driver_error_line[1]=Linking two modules of different data layouts: '' is '' whereas '1' is 'e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v24:32:32-v32:32:32-v48:64:64-v64:64:64-v96:128:128-v128:128:128-v192:256:256-v256:256:256-v512:512:512-v1024:1024:1024-n8:16:32'
driver_error_line[2]=SC compilation failure
driver_error_line[3]=GPGPU, exceed the local data storage limit" UserInfo={NSLocalizedDescription=
driver_error_line[4]=Linking two modules of different data layouts: '' is '' whereas '1' is 'e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v24:32:32-v32:32:32-v48:64:64-v64:64:64-v96:128:128-v128:128:128-v192:256:256-v256:256:256-v512:512:512-v1024:1024:1024-n8:16:32'
driver_error_line[5]=SC compilation failure
driver_error_line[6]=GPGPU, exceed the local data storage limit}
driver_error_user_info[NSLocalizedDescription]=
Linking two modules of different data layouts: '' is '' whereas '1' is 'e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v24:32:32-v32:32:32-v48:64:64-v64:64:64-v96:128:128-v128:128:128-v192:256:256-v256:256:256-v512:512:512-v1024:1024:1024-n8:16:32'
SC compilation failure
GPGPU, exceed the local data storage limit
driver_says_exceed_local_data_storage_limit=YES
done
```

### d0_dk128_wg32_lds32  |  device=0  |  kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64_wg32_lds32  |  exit=0

```
probe=threadgroup-memory-request
device_count=2
device[0]=AMD Radeon HD - FirePro D700
device[1]=AMD Radeon HD - FirePro D700
device_index=0
device_name=AMD Radeon HD - FirePro D700
device_max_threadgroup_memory_length_bytes=32768
metallib=/Users/sam/firellama/vendor/llama.cpp/build-static/bin/kernels/fa.metallib
function=kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64_wg32_lds32
metallib_loaded=YES
function_found=YES
pipeline_build=OK
pipeline_static_threadgroup_memory_bytes=17152
pipeline_threadgroup_bindings=0
pipeline_dynamic_threadgroup_memory_bytes=0
pipeline_requested_threadgroup_memory_bytes=17152
pipeline_requested_threadgroup_memory_source=MTLComputePipelineState.staticThreadgroupMemoryLength+MTLThreadgroupBinding.threadgroupMemoryDataSize
request_exceeds_device_ceiling=NO
thread_execution_width=64
max_total_threads_per_threadgroup=768
driver_error=NONE
done
```

### d0_dk64_plain  |  device=0  |  kernel_flash_attn_ext_vec_amd_dk64_kf16_vf16_w64  |  exit=3

```
probe=threadgroup-memory-request
device_count=2
device[0]=AMD Radeon HD - FirePro D700
device[1]=AMD Radeon HD - FirePro D700
device_index=0
device_name=AMD Radeon HD - FirePro D700
device_max_threadgroup_memory_length_bytes=32768
metallib=/Users/sam/firellama/vendor/llama.cpp/build-static/bin/kernels/fa.metallib
function=kernel_flash_attn_ext_vec_amd_dk64_kf16_vf16_w64
metallib_loaded=YES
function_found=YES
pipeline_build=REFUSED
pipeline_static_threadgroup_memory_bytes=unavailable
pipeline_threadgroup_bindings=unavailable
pipeline_dynamic_threadgroup_memory_bytes=unavailable
pipeline_requested_threadgroup_memory_bytes=unavailable
pipeline_requested_threadgroup_memory_source=refused_pipeline_has_no_state
request_exceeds_device_ceiling=UNKNOWN
driver_error_domain=CompilerError
driver_error_code=2
driver_error_line[0]=Error Domain=CompilerError Code=2 "
driver_error_line[1]=Linking two modules of different data layouts: '' is '' whereas '1' is 'e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v24:32:32-v32:32:32-v48:64:64-v64:64:64-v96:128:128-v128:128:128-v192:256:256-v256:256:256-v512:512:512-v1024:1024:1024-n8:16:32'
driver_error_line[2]=SC compilation failure
driver_error_line[3]=GPGPU, exceed the local data storage limit" UserInfo={NSLocalizedDescription=
driver_error_line[4]=Linking two modules of different data layouts: '' is '' whereas '1' is 'e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v24:32:32-v32:32:32-v48:64:64-v64:64:64-v96:128:128-v128:128:128-v192:256:256-v256:256:256-v512:512:512-v1024:1024:1024-n8:16:32'
driver_error_line[5]=SC compilation failure
driver_error_line[6]=GPGPU, exceed the local data storage limit}
driver_error_user_info[NSLocalizedDescription]=
Linking two modules of different data layouts: '' is '' whereas '1' is 'e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v24:32:32-v32:32:32-v48:64:64-v64:64:64-v96:128:128-v128:128:128-v192:256:256-v256:256:256-v512:512:512-v1024:1024:1024-n8:16:32'
SC compilation failure
GPGPU, exceed the local data storage limit
driver_says_exceed_local_data_storage_limit=YES
done
```

### d0_dk64_lds32  |  device=0  |  kernel_flash_attn_ext_vec_amd_dk64_kf16_vf16_w64_lds32  |  exit=0

```
probe=threadgroup-memory-request
device_count=2
device[0]=AMD Radeon HD - FirePro D700
device[1]=AMD Radeon HD - FirePro D700
device_index=0
device_name=AMD Radeon HD - FirePro D700
device_max_threadgroup_memory_length_bytes=32768
metallib=/Users/sam/firellama/vendor/llama.cpp/build-static/bin/kernels/fa.metallib
function=kernel_flash_attn_ext_vec_amd_dk64_kf16_vf16_w64_lds32
metallib_loaded=YES
function_found=YES
pipeline_build=OK
pipeline_static_threadgroup_memory_bytes=17920
pipeline_threadgroup_bindings=0
pipeline_dynamic_threadgroup_memory_bytes=0
pipeline_requested_threadgroup_memory_bytes=17920
pipeline_requested_threadgroup_memory_source=MTLComputePipelineState.staticThreadgroupMemoryLength+MTLThreadgroupBinding.threadgroupMemoryDataSize
request_exceeds_device_ceiling=NO
thread_execution_width=64
max_total_threads_per_threadgroup=1024
driver_error=NONE
done
```

### d0_dk64_wg32_lds32  |  device=0  |  kernel_flash_attn_ext_vec_amd_dk64_kf16_vf16_w64_wg32_lds32  |  exit=0

```
probe=threadgroup-memory-request
device_count=2
device[0]=AMD Radeon HD - FirePro D700
device[1]=AMD Radeon HD - FirePro D700
device_index=0
device_name=AMD Radeon HD - FirePro D700
device_max_threadgroup_memory_length_bytes=32768
metallib=/Users/sam/firellama/vendor/llama.cpp/build-static/bin/kernels/fa.metallib
function=kernel_flash_attn_ext_vec_amd_dk64_kf16_vf16_w64_wg32_lds32
metallib_loaded=YES
function_found=YES
pipeline_build=OK
pipeline_static_threadgroup_memory_bytes=17920
pipeline_threadgroup_bindings=0
pipeline_dynamic_threadgroup_memory_bytes=0
pipeline_requested_threadgroup_memory_bytes=17920
pipeline_requested_threadgroup_memory_source=MTLComputePipelineState.staticThreadgroupMemoryLength+MTLThreadgroupBinding.threadgroupMemoryDataSize
request_exceeds_device_ceiling=NO
thread_execution_width=64
max_total_threads_per_threadgroup=1024
driver_error=NONE
done
```

### d0_dk256_plain  |  device=0  |  kernel_flash_attn_ext_vec_amd_dk256_kf16_vf16_w64  |  exit=3

```
probe=threadgroup-memory-request
device_count=2
device[0]=AMD Radeon HD - FirePro D700
device[1]=AMD Radeon HD - FirePro D700
device_index=0
device_name=AMD Radeon HD - FirePro D700
device_max_threadgroup_memory_length_bytes=32768
metallib=/Users/sam/firellama/vendor/llama.cpp/build-static/bin/kernels/fa.metallib
function=kernel_flash_attn_ext_vec_amd_dk256_kf16_vf16_w64
metallib_loaded=YES
function_found=YES
pipeline_build=REFUSED
pipeline_static_threadgroup_memory_bytes=unavailable
pipeline_threadgroup_bindings=unavailable
pipeline_dynamic_threadgroup_memory_bytes=unavailable
pipeline_requested_threadgroup_memory_bytes=unavailable
pipeline_requested_threadgroup_memory_source=refused_pipeline_has_no_state
request_exceeds_device_ceiling=UNKNOWN
driver_error_domain=CompilerError
driver_error_code=2
driver_error_line[0]=Error Domain=CompilerError Code=2 "
driver_error_line[1]=Linking two modules of different data layouts: '' is '' whereas '1' is 'e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v24:32:32-v32:32:32-v48:64:64-v64:64:64-v96:128:128-v128:128:128-v192:256:256-v256:256:256-v512:512:512-v1024:1024:1024-n8:16:32'
driver_error_line[2]=SC compilation failure
driver_error_line[3]=GPGPU, exceed the local data storage limit" UserInfo={NSLocalizedDescription=
driver_error_line[4]=Linking two modules of different data layouts: '' is '' whereas '1' is 'e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v24:32:32-v32:32:32-v48:64:64-v64:64:64-v96:128:128-v128:128:128-v192:256:256-v256:256:256-v512:512:512-v1024:1024:1024-n8:16:32'
driver_error_line[5]=SC compilation failure
driver_error_line[6]=GPGPU, exceed the local data storage limit}
driver_error_user_info[NSLocalizedDescription]=
Linking two modules of different data layouts: '' is '' whereas '1' is 'e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v24:32:32-v32:32:32-v48:64:64-v64:64:64-v96:128:128-v128:128:128-v192:256:256-v256:256:256-v512:512:512-v1024:1024:1024-n8:16:32'
SC compilation failure
GPGPU, exceed the local data storage limit
driver_says_exceed_local_data_storage_limit=YES
done
```

### d0_dk256_lds32  |  device=0  |  kernel_flash_attn_ext_vec_amd_dk256_kf16_vf16_w64_lds32  |  exit=0

```
probe=threadgroup-memory-request
device_count=2
device[0]=AMD Radeon HD - FirePro D700
device[1]=AMD Radeon HD - FirePro D700
device_index=0
device_name=AMD Radeon HD - FirePro D700
device_max_threadgroup_memory_length_bytes=32768
metallib=/Users/sam/firellama/vendor/llama.cpp/build-static/bin/kernels/fa.metallib
function=kernel_flash_attn_ext_vec_amd_dk256_kf16_vf16_w64_lds32
metallib_loaded=YES
function_found=YES
pipeline_build=OK
pipeline_static_threadgroup_memory_bytes=16768
pipeline_threadgroup_bindings=0
pipeline_dynamic_threadgroup_memory_bytes=0
pipeline_requested_threadgroup_memory_bytes=16768
pipeline_requested_threadgroup_memory_source=MTLComputePipelineState.staticThreadgroupMemoryLength+MTLThreadgroupBinding.threadgroupMemoryDataSize
request_exceeds_device_ceiling=NO
thread_execution_width=64
max_total_threads_per_threadgroup=512
driver_error=NONE
done
```

### d0_dk256_wg32_lds32  |  device=0  |  kernel_flash_attn_ext_vec_amd_dk256_kf16_vf16_w64_wg32_lds32  |  exit=0

```
probe=threadgroup-memory-request
device_count=2
device[0]=AMD Radeon HD - FirePro D700
device[1]=AMD Radeon HD - FirePro D700
device_index=0
device_name=AMD Radeon HD - FirePro D700
device_max_threadgroup_memory_length_bytes=32768
metallib=/Users/sam/firellama/vendor/llama.cpp/build-static/bin/kernels/fa.metallib
function=kernel_flash_attn_ext_vec_amd_dk256_kf16_vf16_w64_wg32_lds32
metallib_loaded=YES
function_found=YES
pipeline_build=OK
pipeline_static_threadgroup_memory_bytes=16768
pipeline_threadgroup_bindings=0
pipeline_dynamic_threadgroup_memory_bytes=0
pipeline_requested_threadgroup_memory_bytes=16768
pipeline_requested_threadgroup_memory_source=MTLComputePipelineState.staticThreadgroupMemoryLength+MTLThreadgroupBinding.threadgroupMemoryDataSize
request_exceeds_device_ceiling=NO
thread_execution_width=64
max_total_threads_per_threadgroup=768
driver_error=NONE
done
```

### d0_dk512_plain  |  device=0  |  kernel_flash_attn_ext_vec_amd_dk512_kf16_vf16_w64  |  exit=3

```
probe=threadgroup-memory-request
device_count=2
device[0]=AMD Radeon HD - FirePro D700
device[1]=AMD Radeon HD - FirePro D700
device_index=0
device_name=AMD Radeon HD - FirePro D700
device_max_threadgroup_memory_length_bytes=32768
metallib=/Users/sam/firellama/vendor/llama.cpp/build-static/bin/kernels/fa.metallib
function=kernel_flash_attn_ext_vec_amd_dk512_kf16_vf16_w64
metallib_loaded=YES
function_found=YES
pipeline_build=REFUSED
pipeline_static_threadgroup_memory_bytes=unavailable
pipeline_threadgroup_bindings=unavailable
pipeline_dynamic_threadgroup_memory_bytes=unavailable
pipeline_requested_threadgroup_memory_bytes=unavailable
pipeline_requested_threadgroup_memory_source=refused_pipeline_has_no_state
request_exceeds_device_ceiling=UNKNOWN
driver_error_domain=CompilerError
driver_error_code=2
driver_error_line[0]=Error Domain=CompilerError Code=2 "
driver_error_line[1]=Linking two modules of different data layouts: '' is '' whereas '1' is 'e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v24:32:32-v32:32:32-v48:64:64-v64:64:64-v96:128:128-v128:128:128-v192:256:256-v256:256:256-v512:512:512-v1024:1024:1024-n8:16:32'
driver_error_line[2]=SC compilation failure
driver_error_line[3]=GPGPU, exceed the local data storage limit" UserInfo={NSLocalizedDescription=
driver_error_line[4]=Linking two modules of different data layouts: '' is '' whereas '1' is 'e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v24:32:32-v32:32:32-v48:64:64-v64:64:64-v96:128:128-v128:128:128-v192:256:256-v256:256:256-v512:512:512-v1024:1024:1024-n8:16:32'
driver_error_line[5]=SC compilation failure
driver_error_line[6]=GPGPU, exceed the local data storage limit}
driver_error_user_info[NSLocalizedDescription]=
Linking two modules of different data layouts: '' is '' whereas '1' is 'e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v24:32:32-v32:32:32-v48:64:64-v64:64:64-v96:128:128-v128:128:128-v192:256:256-v256:256:256-v512:512:512-v1024:1024:1024-n8:16:32'
SC compilation failure
GPGPU, exceed the local data storage limit
driver_says_exceed_local_data_storage_limit=YES
done
```

### d0_dk512_lds32  |  device=0  |  kernel_flash_attn_ext_vec_amd_dk512_kf16_vf16_w64_lds32  |  exit=0

```
probe=threadgroup-memory-request
device_count=2
device[0]=AMD Radeon HD - FirePro D700
device[1]=AMD Radeon HD - FirePro D700
device_index=0
device_name=AMD Radeon HD - FirePro D700
device_max_threadgroup_memory_length_bytes=32768
metallib=/Users/sam/firellama/vendor/llama.cpp/build-static/bin/kernels/fa.metallib
function=kernel_flash_attn_ext_vec_amd_dk512_kf16_vf16_w64_lds32
metallib_loaded=YES
function_found=YES
pipeline_build=OK
pipeline_static_threadgroup_memory_bytes=16576
pipeline_threadgroup_bindings=0
pipeline_dynamic_threadgroup_memory_bytes=0
pipeline_requested_threadgroup_memory_bytes=16576
pipeline_requested_threadgroup_memory_source=MTLComputePipelineState.staticThreadgroupMemoryLength+MTLThreadgroupBinding.threadgroupMemoryDataSize
request_exceeds_device_ceiling=NO
thread_execution_width=64
max_total_threads_per_threadgroup=512
driver_error=NONE
done
```

### d0_dk40_plain  |  device=0  |  kernel_flash_attn_ext_vec_amd_dk40_kf16_vf16_w64  |  exit=0

```
probe=threadgroup-memory-request
device_count=2
device[0]=AMD Radeon HD - FirePro D700
device[1]=AMD Radeon HD - FirePro D700
device_index=0
device_name=AMD Radeon HD - FirePro D700
device_max_threadgroup_memory_length_bytes=32768
metallib=/Users/sam/firellama/vendor/llama.cpp/build-static/bin/kernels/fa.metallib
function=kernel_flash_attn_ext_vec_amd_dk40_kf16_vf16_w64
metallib_loaded=YES
function_found=YES
pipeline_build=OK
pipeline_static_threadgroup_memory_bytes=23552
pipeline_threadgroup_bindings=0
pipeline_dynamic_threadgroup_memory_bytes=0
pipeline_requested_threadgroup_memory_bytes=23552
pipeline_requested_threadgroup_memory_source=MTLComputePipelineState.staticThreadgroupMemoryLength+MTLThreadgroupBinding.threadgroupMemoryDataSize
request_exceeds_device_ceiling=NO
thread_execution_width=64
max_total_threads_per_threadgroup=1024
driver_error=NONE
done
```

### d0_dk72_plain  |  device=0  |  kernel_flash_attn_ext_vec_amd_dk72_kf16_vf16_w64  |  exit=0

```
probe=threadgroup-memory-request
device_count=2
device[0]=AMD Radeon HD - FirePro D700
device[1]=AMD Radeon HD - FirePro D700
device_index=0
device_name=AMD Radeon HD - FirePro D700
device_max_threadgroup_memory_length_bytes=32768
metallib=/Users/sam/firellama/vendor/llama.cpp/build-static/bin/kernels/fa.metallib
function=kernel_flash_attn_ext_vec_amd_dk72_kf16_vf16_w64
metallib_loaded=YES
function_found=YES
pipeline_build=OK
pipeline_static_threadgroup_memory_bytes=19968
pipeline_threadgroup_bindings=0
pipeline_dynamic_threadgroup_memory_bytes=0
pipeline_requested_threadgroup_memory_bytes=19968
pipeline_requested_threadgroup_memory_source=MTLComputePipelineState.staticThreadgroupMemoryLength+MTLThreadgroupBinding.threadgroupMemoryDataSize
request_exceeds_device_ceiling=NO
thread_execution_width=64
max_total_threads_per_threadgroup=1024
driver_error=NONE
done
```

### d0_dk80_plain  |  device=0  |  kernel_flash_attn_ext_vec_amd_dk80_kf16_vf16_w64  |  exit=0

```
probe=threadgroup-memory-request
device_count=2
device[0]=AMD Radeon HD - FirePro D700
device[1]=AMD Radeon HD - FirePro D700
device_index=0
device_name=AMD Radeon HD - FirePro D700
device_max_threadgroup_memory_length_bytes=32768
metallib=/Users/sam/firellama/vendor/llama.cpp/build-static/bin/kernels/fa.metallib
function=kernel_flash_attn_ext_vec_amd_dk80_kf16_vf16_w64
metallib_loaded=YES
function_found=YES
pipeline_build=OK
pipeline_static_threadgroup_memory_bytes=22016
pipeline_threadgroup_bindings=0
pipeline_dynamic_threadgroup_memory_bytes=0
pipeline_requested_threadgroup_memory_bytes=22016
pipeline_requested_threadgroup_memory_source=MTLComputePipelineState.staticThreadgroupMemoryLength+MTLThreadgroupBinding.threadgroupMemoryDataSize
request_exceeds_device_ceiling=NO
thread_execution_width=64
max_total_threads_per_threadgroup=1024
driver_error=NONE
done
```

### d0_dk160_plain  |  device=0  |  kernel_flash_attn_ext_vec_amd_dk160_kf16_vf16_w64  |  exit=0

```
probe=threadgroup-memory-request
device_count=2
device[0]=AMD Radeon HD - FirePro D700
device[1]=AMD Radeon HD - FirePro D700
device_index=0
device_name=AMD Radeon HD - FirePro D700
device_max_threadgroup_memory_length_bytes=32768
metallib=/Users/sam/firellama/vendor/llama.cpp/build-static/bin/kernels/fa.metallib
function=kernel_flash_attn_ext_vec_amd_dk160_kf16_vf16_w64
metallib_loaded=YES
function_found=YES
pipeline_build=OK
pipeline_static_threadgroup_memory_bytes=10624
pipeline_threadgroup_bindings=0
pipeline_dynamic_threadgroup_memory_bytes=0
pipeline_requested_threadgroup_memory_bytes=10624
pipeline_requested_threadgroup_memory_source=MTLComputePipelineState.staticThreadgroupMemoryLength+MTLThreadgroupBinding.threadgroupMemoryDataSize
request_exceeds_device_ceiling=NO
thread_execution_width=64
max_total_threads_per_threadgroup=1024
driver_error=NONE
done
```

### d1_dk128_plain  |  device=1  |  kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64  |  exit=3

```
probe=threadgroup-memory-request
device_count=2
device[0]=AMD Radeon HD - FirePro D700
device[1]=AMD Radeon HD - FirePro D700
device_index=1
device_name=AMD Radeon HD - FirePro D700
device_max_threadgroup_memory_length_bytes=32768
metallib=/Users/sam/firellama/vendor/llama.cpp/build-static/bin/kernels/fa.metallib
function=kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64
metallib_loaded=YES
function_found=YES
pipeline_build=REFUSED
pipeline_static_threadgroup_memory_bytes=unavailable
pipeline_threadgroup_bindings=unavailable
pipeline_dynamic_threadgroup_memory_bytes=unavailable
pipeline_requested_threadgroup_memory_bytes=unavailable
pipeline_requested_threadgroup_memory_source=refused_pipeline_has_no_state
request_exceeds_device_ceiling=UNKNOWN
driver_error_domain=CompilerError
driver_error_code=2
driver_error_line[0]=Error Domain=CompilerError Code=2 "
driver_error_line[1]=Linking two modules of different data layouts: '' is '' whereas '1' is 'e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v24:32:32-v32:32:32-v48:64:64-v64:64:64-v96:128:128-v128:128:128-v192:256:256-v256:256:256-v512:512:512-v1024:1024:1024-n8:16:32'
driver_error_line[2]=SC compilation failure
driver_error_line[3]=GPGPU, exceed the local data storage limit" UserInfo={NSLocalizedDescription=
driver_error_line[4]=Linking two modules of different data layouts: '' is '' whereas '1' is 'e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v24:32:32-v32:32:32-v48:64:64-v64:64:64-v96:128:128-v128:128:128-v192:256:256-v256:256:256-v512:512:512-v1024:1024:1024-n8:16:32'
driver_error_line[5]=SC compilation failure
driver_error_line[6]=GPGPU, exceed the local data storage limit}
driver_error_user_info[NSLocalizedDescription]=
Linking two modules of different data layouts: '' is '' whereas '1' is 'e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v24:32:32-v32:32:32-v48:64:64-v64:64:64-v96:128:128-v128:128:128-v192:256:256-v256:256:256-v512:512:512-v1024:1024:1024-n8:16:32'
SC compilation failure
GPGPU, exceed the local data storage limit
driver_says_exceed_local_data_storage_limit=YES
done
```

### d1_dk128_lds32  |  device=1  |  kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64_lds32  |  exit=0

```
probe=threadgroup-memory-request
device_count=2
device[0]=AMD Radeon HD - FirePro D700
device[1]=AMD Radeon HD - FirePro D700
device_index=1
device_name=AMD Radeon HD - FirePro D700
device_max_threadgroup_memory_length_bytes=32768
metallib=/Users/sam/firellama/vendor/llama.cpp/build-static/bin/kernels/fa.metallib
function=kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64_lds32
metallib_loaded=YES
function_found=YES
pipeline_build=OK
pipeline_static_threadgroup_memory_bytes=17152
pipeline_threadgroup_bindings=0
pipeline_dynamic_threadgroup_memory_bytes=0
pipeline_requested_threadgroup_memory_bytes=17152
pipeline_requested_threadgroup_memory_source=MTLComputePipelineState.staticThreadgroupMemoryLength+MTLThreadgroupBinding.threadgroupMemoryDataSize
request_exceeds_device_ceiling=NO
thread_execution_width=64
max_total_threads_per_threadgroup=512
driver_error=NONE
done
```

### d1_dk128_wg32_lds32  |  device=1  |  kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64_wg32_lds32  |  exit=0

```
probe=threadgroup-memory-request
device_count=2
device[0]=AMD Radeon HD - FirePro D700
device[1]=AMD Radeon HD - FirePro D700
device_index=1
device_name=AMD Radeon HD - FirePro D700
device_max_threadgroup_memory_length_bytes=32768
metallib=/Users/sam/firellama/vendor/llama.cpp/build-static/bin/kernels/fa.metallib
function=kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64_wg32_lds32
metallib_loaded=YES
function_found=YES
pipeline_build=OK
pipeline_static_threadgroup_memory_bytes=17152
pipeline_threadgroup_bindings=0
pipeline_dynamic_threadgroup_memory_bytes=0
pipeline_requested_threadgroup_memory_bytes=17152
pipeline_requested_threadgroup_memory_source=MTLComputePipelineState.staticThreadgroupMemoryLength+MTLThreadgroupBinding.threadgroupMemoryDataSize
request_exceeds_device_ceiling=NO
thread_execution_width=64
max_total_threads_per_threadgroup=768
driver_error=NONE
done
```

### d1_dk64_lds32  |  device=1  |  kernel_flash_attn_ext_vec_amd_dk64_kf16_vf16_w64_lds32  |  exit=0

```
probe=threadgroup-memory-request
device_count=2
device[0]=AMD Radeon HD - FirePro D700
device[1]=AMD Radeon HD - FirePro D700
device_index=1
device_name=AMD Radeon HD - FirePro D700
device_max_threadgroup_memory_length_bytes=32768
metallib=/Users/sam/firellama/vendor/llama.cpp/build-static/bin/kernels/fa.metallib
function=kernel_flash_attn_ext_vec_amd_dk64_kf16_vf16_w64_lds32
metallib_loaded=YES
function_found=YES
pipeline_build=OK
pipeline_static_threadgroup_memory_bytes=17920
pipeline_threadgroup_bindings=0
pipeline_dynamic_threadgroup_memory_bytes=0
pipeline_requested_threadgroup_memory_bytes=17920
pipeline_requested_threadgroup_memory_source=MTLComputePipelineState.staticThreadgroupMemoryLength+MTLThreadgroupBinding.threadgroupMemoryDataSize
request_exceeds_device_ceiling=NO
thread_execution_width=64
max_total_threads_per_threadgroup=1024
driver_error=NONE
done
```

### d1_dk256_lds32  |  device=1  |  kernel_flash_attn_ext_vec_amd_dk256_kf16_vf16_w64_lds32  |  exit=0

```
probe=threadgroup-memory-request
device_count=2
device[0]=AMD Radeon HD - FirePro D700
device[1]=AMD Radeon HD - FirePro D700
device_index=1
device_name=AMD Radeon HD - FirePro D700
device_max_threadgroup_memory_length_bytes=32768
metallib=/Users/sam/firellama/vendor/llama.cpp/build-static/bin/kernels/fa.metallib
function=kernel_flash_attn_ext_vec_amd_dk256_kf16_vf16_w64_lds32
metallib_loaded=YES
function_found=YES
pipeline_build=OK
pipeline_static_threadgroup_memory_bytes=16768
pipeline_threadgroup_bindings=0
pipeline_dynamic_threadgroup_memory_bytes=0
pipeline_requested_threadgroup_memory_bytes=16768
pipeline_requested_threadgroup_memory_source=MTLComputePipelineState.staticThreadgroupMemoryLength+MTLThreadgroupBinding.threadgroupMemoryDataSize
request_exceeds_device_ceiling=NO
thread_execution_width=64
max_total_threads_per_threadgroup=512
driver_error=NONE
done
```
