# The declared flash-attention contract on wave64 AMD

Status: declared, clause (c) checked in CI.
Ticket: `.scratch/firellama-maxperf/issues/38-declared-fa-contract.md`.
Spec: `.scratch/firellama-maxperf/spec.md`, Revision 2 (which supersedes the earlier body).

Three clauses. (a) and (b) are declarations with the measurement that backs them. (c) is the
clause that would have caught the plain-form refusal, and it is enforced by
`tools/check-fa-amd-contract.sh` on every pull request (the `fa-amd-contract` job in
`.github/workflows/build.yml`).

The kernel family is `kernel_flash_attn_ext_vec_amd_*`. The selector is
`ggml_metal_op_flash_attn_ext` in `ggml/src/ggml-metal/ggml-metal-ops.cpp`, tracked as
`patches/llama/metal/0008-flash-attention-amd.patch` (the pinned upstream file plus the
series; `vendor/llama.cpp` is gitignored and can be stale, so the series is the source of
truth for this contract).

## (a) Which kernel the selector requests on wave64

On a wave64 device (`simd_width == 64`, this hardware's dispatch width) the FA AMD vec path
requests

    kernel_flash_attn_ext_vec_amd_dk<D>_k<K>_v<V>_w64

- `<D>` is a head size the gate admits: 64, 128, 256, 512, 384 and 640 (the last two for
  Turbo KV only), 72 and 40/80/160 (f16 K/V only), and the asymmetric MLA forms
  `dk576_dv512` and `dk320_dv256`.
- `<K>` and `<V>` are the KV dequant suffixes: `f16`, `q8_0`, `q4_0`, `turbo2`, `turbo3`,
  `turbo4`.
- `_wg32` is appended to that name when the split-cache path is on (`fa_amd_nwg > 1`).

The plain `_w64` name is requested first. When that build is refused, or when
`TOSH_FA_AMD_LDS32` is set, the same path requests the name's `_lds32` twin
(`..._w64_lds32`, or `..._w64_wg32_lds32` when the split-cache name was the primary), halves
`fa_amd_nsg`, and dispatches the twin. A name refused once is memoised and not requested again
(`ggml_metal_fa_amd_pipeline`), so the failed build is paid once per process, not per layer.

On this hardware the plain `_w64` request is refused for dk64, dk128, dk256 and dk512 (record
below), so the twin is the request that builds. Which of the two builds actually executes at
runtime is a code-read inference from the source, not a runtime log; the pipelined engine run
ticket 16 waits for is what would confirm it.

## (b) The selected variant is under the device's threadgroup memory ceiling

Both FirePro D700s report `device_max_threadgroup_memory_length_bytes = 32768`. Every FA AMD
variant measured as building requests between 10624 and 23552 bytes; the largest of them,
`dk40_kf16_vf16_w64`, is 9216 bytes under the ceiling. The variant the twin route selects on
this device, `dk128_kf16_vf16_w64_lds32`, requests 17152 bytes, 15616 under.

No byte count is asserted for a refused pipeline. Metal exposes a pipeline's static threadgroup
bytes only through a built pipeline state, and a refused pipeline has none; those requests are
recorded as `unavailable`, which is a measurement outcome, not a zero. Nothing here says the
refused requests are over the ceiling: the plain request is unmeasurable on this OS by design,
and the refusal is not attributed to a byte count (see "What this contract does not assert").

## (c) No build the probe refused on this device is a dead end

The selector requests the plain `_w64` name first and falls back to the `_lds32` twin when that
build is refused. This contract does not assert the stronger statement that the selector never
asks for a name the probe refused: on this tree it does ask, once per process. Ticket 35 leaves
two readings standing that the data cannot separate (the twin exists because the plain form
overflows, or the plain names were never viable), and demoting the plain request is ticket 39,
blocked on the engine run. Asserting the stronger statement would take the second reading as
proved.

What is asserted and checked is that the refusal is survivable:

> For every name in the refusal record below that the wave64 vec selector can construct, the
> selector also constructs that name's `_lds32` twin, and that twin is not in the refusal
> record. A request the probe refused with no replacement it did not refuse is a dead end,
> and a dead end fails the check.

The clause is scoped to this device: what it enforces is this hardware's refusal record, not a
claim about wave64 AMD in general, so a device on which the plain form builds has nothing here
to trip over. An empty record is not a pass but an unusable input (the same rule as the empty
CSV in the perf gate): a guard that goes green on an empty list is the failure mode this
exists to avoid.

`tools/check-fa-amd-contract.sh` performs the comparison: the names come from the tracked
series, the refusals come from this file's record (existing probe output, not a new
measurement). The check exits non-zero if the record is empty, if the selector no longer
constructs the vec name or the `_lds32` twin, or on any dead end. `FA_REFUSED_EXTRA` seeds
extra refusals so the failure path can be demonstrated without editing this file.

Three bounds on that comparison, stated so a green is not read as more than it is:

- Matching is by the form the selector constructs, not by evaluating the width gate: a refused
  name of that form is treated as requestable even where the gate would not select it. That
  direction can add a failure, never hide one.
- "Not in the refusal record" is the positive evidence the comparison can produce. The twins
  that build, and their byte counts, are in the method section below; the check does not re-run
  the probe, and a twin the probe never requested is not covered as measured.
- The record holds what the probe was asked, which is the `kf16_vf16_w64` column of the type
  matrix. Other K/V pairs and the Turbo widths were not probed.

## The refusal record

Produced by `tools/metal-probe/threadgroupprobe.m` on both D700s, 2026-10-18, and reproduced
verbatim from the evidence file named under the method line. One name per line; the check reads
exactly the lines between the markers.

<!-- refused-names-begin -->
kernel_flash_attn_ext_vec_amd_dk64_kf16_vf16_w64
kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64
kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64_wg32
kernel_flash_attn_ext_vec_amd_dk256_kf16_vf16_w64
kernel_flash_attn_ext_vec_amd_dk512_kf16_vf16_w64
<!-- refused-names-end -->

Each of those five names is refused at pipeline creation
(`Error Domain=CompilerError Code=2`, the driver's third message being
`GPGPU, exceed the local data storage limit`), and each has an `_lds32` twin that builds:

| refused plain name | twin that builds | twin request (bytes) |
|---|---|---|
| `..._dk64_kf16_vf16_w64` | `..._dk64_kf16_vf16_w64_lds32` | 17920 |
| `..._dk128_kf16_vf16_w64` | `..._dk128_kf16_vf16_w64_lds32` | 17152 |
| `..._dk128_kf16_vf16_w64_wg32` | `..._dk128_kf16_vf16_w64_wg32_lds32` | 17152 |
| `..._dk256_kf16_vf16_w64` | `..._dk256_kf16_vf16_w64_lds32` | 16768 |
| `..._dk512_kf16_vf16_w64` | `..._dk512_kf16_vf16_w64_lds32` | 16576 |

The set of plain widths that refuse, `{64, 128, 256, 512}`, is exactly the set of widths that
carry an `_lds32` twin; the plain widths that build, `{40, 72, 80, 160}`, carry none. Width, not
measured size, separates the two sets: plain `dk40` builds at 23552 bytes while plain `dk128`
refuses with an unmeasurable request.

## Method line

- Machine: `Sams-Mac-Pro`, Intel Mac Pro, x86_64, macOS 15.8 (24H23), Darwin 24.6.0.
- Devices: two `AMD Radeon HD - FirePro D700`, device indices 0 and 1; both report
  `device_max_threadgroup_memory_length_bytes = 32768`.
- Probe: `tools/metal-probe/threadgroupprobe.m`, sha256
  `267f6ad6d1c7e3720acada94b812542404cf9aab7e339e2b3261a072e8405cc1`, compiled with
  `clang -fobjc-arc -framework Foundation -framework Metal`.
- Metallib: `vendor/llama.cpp/build-static/bin/kernels/fa.metallib`, sha256
  `af4b13d4ec0f6c7ab9e214d62bb8e9f56417e90e5b9bde5b4cb84efcef0bfe9e`, 14692576 bytes. The
  `_lds32` twins live in this library.
- Environment for every run: `GGML_METAL_DEVICES=2`, `GGML_METAL_VRAM_RESERVE_MB=1024`,
  `GGML_METAL_SIMDGROUP_REDUCTION_DISABLE=1`.
- Invocation: `threadgroupprobe <device> <metallib> <function>` under a 180 s alarm; exit 0
  built, 3 refused, 2 probe error. Every run finished in about 0.5 s; no run hit the alarm.
- N: 26 runs over 21 distinct (device, variant) pairs; repeats byte-identical under `cmp`. No
  warmups taken or discarded: the quantity is a byte count read at pipeline creation, not a
  duration, so there is no warmup policy to state.
- What could not be run: the plain `dk64`, `dk128`, `dk256`, `dk512` and `dk128_wg32` requests
  (unobtainable, no pipeline state), and plain `dk64_wg32`, which was never probed. The
  `dk384`/`dk640` Turbo widths and every K/V pair other than `kf16_vf16` were not probed.
- Raw output: `.scratch/firellama-maxperf/evidence/threadgroup-memory-2026-10-18.md`, which also
  carries the driver's error string verbatim; the record above is reproduced from it rather
  than referenced. The symbol-presence check `tools/check-fa-amd-kernels.sh` is a separate gate
  and states its own bound: presence is not usability.

## What this contract does not assert

- No byte count for a refused pipeline, and no claim that the refused requests exceed the
  ceiling. That measurement is unobtainable by design on this OS.
- Not that the plain form is universally unviable. Two readings survive ticket 35's data, and
  the contract takes neither.
- Not that the selector never requests a refused name. That ordering change is ticket 39, and
  it stays blocked until the engine run says which reading holds.
- Not that the twin executes at runtime on this machine. That is ticket 16's pipelined engine
  run.
