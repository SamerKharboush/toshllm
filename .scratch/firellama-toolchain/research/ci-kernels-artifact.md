# CI kernels artifact — investigation notes

Date: 2026-10-02. Read-only investigation; nothing in the repo was modified.

## Headline

A CI-built DMG **does** ship a `kernels/` directory (25 `.metallib` + `fingerprint`, 39 MB),
and every one of those 25 metallibs **loads successfully on this Intel x86_64 Mac Pro with two
AMD FirePro D700s** via `newLibraryWithURL:`. So the CI kernels are usable on Intel, and they
avoid the ~143 s runtime compile. The local beta DMG ships **no** metallibs at all.

## 1. Runner architecture for `macos-26`

Source: `actions/runner-images` README "Available Images" table (fetched 2026-10-02).

| Image | Architecture | YAML label |
| --- | --- | --- |
| macOS 26 | **x64** | `macos-latest-large`, **`macos-26-intel`**, `macos-26-large` |
| macOS 26 Arm64 | **arm64** | `macos-latest`, **`macos-26`**, `macos-26-xlarge` |
| macOS 15 | x64 | `macos-15-large`, **`macos-15-intel`** |
| macOS 15 Arm64 | arm64 | `macos-15`, `macos-15-xlarge` |
| macOS 14 | x64 | `macos-14-large` (no plain `macos-14` for x64) |
| macOS 14 Arm64 | arm64 | `macos-14`, `macos-14-xlarge` (deprecated) |
| Xcode 27 | arm64 | `xcode-27`, `xcode-27-xlarge` |

`macos-26` is **arm64**. Intel macOS labels that exist right now: `macos-26-intel`,
`macos-15-intel` (plus the `-large` variants). `macos-13` is gone.

The metallib itself turned out to be architecture-neutral (see §4), so the runner arch does not
gate usability; it only matters for how fast the engines themselves build.

## 2. What the CI path produced

```
$ gh run list --workflow build.yml --limit 20 --json databaseId,conclusion,event,headBranch,createdAt,displayTitle
{"conclusion":"success","createdAt":"2026-10-01T23:24:55Z","databaseId":36940675656,"displayTitle":"release: 0.87.13","event":"push","headBranch":"main"}
{"conclusion":"success","createdAt":"2026-10-01T23:24:55Z","databaseId":36940675329,"displayTitle":"release: 0.87.13","event":"push","headBranch":"v0.87.13"}
{"conclusion":"action_required","createdAt":"2026-09-30T11:21:16Z","databaseId":36708019058,"displayTitle":"Firellama v0.87.11","event":"pull_request","headBranch":"firellama-v0.87.11"}
{"conclusion":"success","createdAt":"2026-09-29T22:52:13Z","databaseId":36642070322,...,"event":"push","headBranch":"main"}
{"conclusion":"success","createdAt":"2026-09-29T22:52:13Z","databaseId":36642070020,...,"event":"push","headBranch":"v0.87.12"}
... (older tag pushes 0.87.11 down to 0.87.5, all success)
```

No `workflow_dispatch` runs in the last 20; the most recent non-PR success is the tag push
`v0.87.13` = run **36940675329** (branch `v0.87.13`). Used that one.

Jobs: `Build standard (x86_64)` success, `Build noavx2 (x86_64)` success,
`Unit tests` skipped, `Publish release` success.

Log evidence (`gh run view 36940675329 --log | grep -iE "metal compiler|precompiled|metallib"`):

```
5444: Build standard (x86_64)  Metal compiler available — will precompile default.metallib (fast model load)
280:  Build noavx2 (x86_64)  Metal compiler available — will precompile default.metallib (fast model load)
8653: Build standard (x86_64)  precompiled 26 metal libraries ( 39M)
3492: Build noavx2 (x86_64)  precompiled 26 metal libraries ( 39M)
3772: Build noavx2 (x86_64)  precompiled default.metallib for speech engine
4893: Build noavx2 (x86_64)  precompiled default.metallib for image engine
```

So CI **did** have a Metal compiler and **did** precompile. (Script says "26"; the shipped dir has
25 `.metallib` + `fingerprint` — see §3. One library is likely named the same in two source
files, or the count includes the fingerprint line.)

Artifacts (from the `Publish release` log, since `gh api .../artifacts` returns 404 on this fork
while `gh run download` works):

```
- dmg-noavx2   (ID: 11200571237, Size: 73242865)
- dmg-standard (ID: 11200278099, Size: 74196766, sha256:3e353e6a12d455a08847f296d4f12c5208850328cf3b0a166b28f7c5dcd4bef3)
```

Downloaded:

```
$ gh run download 36940675329 -n dmg-standard -D /tmp/ci-dmg-36940675329
/tmp/ci-dmg-36940675329/ToshLLM-v0.87.13.dmg   74512886 bytes
```

## 3. Inside the CI artifact

Mounted read-only at `/tmp/ci-dmg-mount` (since detached).

`ToshLLM.app/Contents/Resources/bin/`:

```
drwxr-xr-x   28 sam staff    896 Oct  2 01:37 kernels
-rwxr-xr-x   16 sam staff 15954960 Oct  2 01:37 llama-bench
-rwxr-xr-x   16 sam staff 15893184 Oct  2 01:37 llama-perplexity
-rwxr-xr-x   16 sam staff 22293440 Oct  2 01:37 llama-server
-rwxr-xr-x   16 sam staff  8119120 Oct  2 01:37 test-backend-ops
```

`kernels/`: 25 `.metallib` + `fingerprint`, `du -sh` = **39 M**.

```
argsort.metallib        43173      mul_mm.metallib          2701267
binbcast.metallib       77339      mul_mm_w64.metallib      2145374
conv.metallib          103299      mul_mv.metallib          5269058
fa.metallib         22102311      mul_mv_w64.metallib       2855772
fa_w64.metallib       3552971      norm.metallib              96045
fingerprint              1804      pool.metallib              18704
gated_delta_net.metallib 89178     quantize.metallib         760633
misc.metallib          276808      reduce.metallib            28815
rope.metallib            76754      softmax.metallib           37446
solve_tri.metallib        7953      ssm.metallib               74084
tri.metallib             59180      tosh_moe.metallib          52822
turbo.metallib           129928      unary.metallib            112060
upscale.metallib          19707      wkv.metallib               14788
```

`kernels/fingerprint` — 25 lines, first 5:

```
argsort 5b17cb38b5aaf02627abc6e10bf9b5eec22941efdcf064dcb781ce5c4d4060dd
binbcast a2352caea835bfcbc37edbc10f3f4793196f3aa3f558dee969c378138802a84f
conv 5ac94030b696f14882b5335d81a97f4d1cf85c5ed761afa8a9de353fe43a0c22
fa_w64 b7a09c49cedd9fca329855327c1b229880d1b5e3ecf50cf42b674798b9951ca0
fa 04c273cf869e5358f91fcc29e36fb6d0ad1004e519f8241e038216ce77ca004d
```

Other engine dirs **do** have theirs:

```
bin-audio/default.metallib   11246673   (+ whisper-cli 3955584, whisper-server 4410752)
bin-image/default.metallib   11279398   (+ sd-cli 42404240)
```

`bin/` (llama) has **no** `default.metallib` — it has `kernels/` instead, per the patch.

## 4. Architecture evidence inside a metallib

`file` on three metallibs:

```
argsort.metallib: MetalLib executable (MacOS), version 1.2.7
fa.metallib:      MetalLib executable (MacOS), version 1.2.7
mul_mv.metallib:  MetalLib executable (MacOS), version 1.2.7
```

Container magic is `MTLB`, one occurrence per file (the metallib is a single archive, not a fat
Mach-O), so `otool -hv` is not applicable.

`strings` tokens found (identical set in all three files):

```
Apple metal version 32023.883 (metalfe-32023.883)
Metal
air64_v26-apple-macosx14.0.0
air.*      (air.arg_type_name, air.thread_position_in_threadgroup, air.simd_*, ...)
macosx14.0.0
```

Tokens **not** found: `x86_64`, `arm64`, `i386`, `mtlgpufamily`, `MTLGPUFamily*`, `appleN`,
`macN`.

Interpretation: `air64_v26-apple-macosx14.0.0` is the **Metal IR (AIR) target triple**, i.e. the
GPU-side intermediate language. `air64` = 64-bit pointer AIR, `apple-macosx14.0.0` = deployment
target. There is no host-CPU slice in a metallib at all — GPU function binaries are built for
GPU families, not for x86_64/arm64. So the arch of the CI runner (`macos-26` = arm64) is
**irrelevant** to whether the metallib loads on x86_64.

Decisive runtime check (no Metal toolchain needed — just `Metal.framework` from the OS and
clang from Command Line Tools):

```objc
id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
[dev newLibraryWithURL:[NSURL fileURLWithPath:path] error:&e]
```

Compiled with `clang -fobjc-arc -framework Foundation -framework Metal` and run on this machine
(Intel x86_64 Mac Pro, 2x AMD FirePro D700, Metal 2):

```
device=AMD Radeon HD - FirePro D700
LOAD_OK   argsort.metallib             functions=7
LOAD_OK   binbcast.metallib            functions=11
LOAD_OK   conv.metallib                functions=19
LOAD_OK   fa.metallib                  functions=1581
LOAD_OK   fa_w64.metallib              functions=281
LOAD_OK   gated_delta_net.metallib     functions=7
LOAD_OK   misc.metallib                functions=51
LOAD_OK   mul_mm.metallib              functions=167
LOAD_OK   mul_mm_w64.metallib          functions=156
LOAD_OK   mul_mv.metallib              functions=515
LOAD_OK   mul_mv_w64.metallib          functions=284
LOAD_OK   norm.metallib                functions=15
LOAD_OK   pool.metallib                functions=4
LOAD_OK   quantize.metallib            functions=123
LOAD_OK   reduce.metallib              functions=5
LOAD_OK   rope.metallib                functions=8
LOAD_OK   softmax.metallib             functions=5
LOAD_OK   solve_tri.metallib           functions=1
LOAD_OK   ssm.metallib                 functions=11
LOAD_OK   tosh_moe.metallib            functions=11
LOAD_OK   tri.metallib                 functions=12
LOAD_OK   turbo.metallib               functions=17
LOAD_OK   unary.metallib               functions=19
LOAD_OK   upscale.metallib             functions=3
LOAD_OK   wkv.metallib                 functions=2
summary ok=25 fail=0
mul_mv kernel_mul_mv_q4_0_f32 -> FOUND
```

All 25 load, ~0.19 s total for the whole directory. The speech and image default.metallibs also
load (953 and 957 functions).

So: the metallibs are host-arch-neutral **and** confirmed loadable on an Intel AMD-Metal-2 GPU.

Engine binaries (the arch that must load the metallib), all x86_64 single-arch:

```
$ file /tmp/ci-dmg-mount/ToshLLM.app/Contents/Resources/bin/llama-server
... Mach-O 64-bit executable x86_64
$ otool -hv .../llama-server
Mach header
      magic  cputype cpusubtype  caps    filetype ncmds sizeofcmds      flags
MH_MAGIC_64   X86_64        ALL  0x00     EXECUTE    26       3080   NOUNDEFS DYLDLINK ...

$ file /Users/sam/firellama/vendor/llama.cpp/build-static/bin/llama-server
... Mach-O 64-bit executable x86_64
$ otool -hv ...
MH_MAGIC_64   X86_64        ALL  0x00     EXECUTE    25       3064   NOUNDEFS DYLDLINK ...
```

Local `dist/ToshLLM.app` has **no** `kernels/` and **no** `.metallib` anywhere
(`find dist/ToshLLM.app -name '*.metallib'` → 0 results), so the same probe cannot be run there.

Note on pipeline state: `newComputePipelineStateWithFunction:` on
`kernel_mul_mv_q4_0_f32` aborts with

```
failed assertion `Compute Pipeline Descriptor Validation
function kernel_mul_mv_q4_0_f32 cannot be used to build a pipeline state. Use
newFunctionWithName:constantValues:... to get the specialized function'
```

That is expected for the patched kernels (they take a `ggml_metal_kargs_*` struct via constant
values), not an arch problem. The library load itself, which is what `device.m` gates on, succeeds.

## 5. Local beta DMG vs CI DMG

Both DMGs were mounted read-only. Kernel presence differs:

| | `dist/ToshLLM-v0.87.14-beta.1.dmg` (local) | CI `ToshLLM-v0.87.13.dmg` |
| --- | --- | --- |
| `bin/kernels/` | absent | present, 25 `.metallib` + fingerprint, 39 M |
| any `.metallib` in app | 0 | 27 (25 + 2 `default.metallib`) |
| `fingerprint` files | 0 | 1 |
| sha256 | `1a21a53796da21d6a3d4d0296e2ea9958a726595accb4cda030aaabedfd2310e` | `f94728df0e5c79011bdb336c792060bfe921499c39a97de0b1de3b607890e972` |

`dist/checksums.txt` (local):

```
1a21a53796da21d6a3d4d0296e2ea9958a726595accb4cda030aaabedfd2310e  ToshLLM-v0.87.14-beta.1.dmg
```

It matches the local DMG exactly (verified with `shasum -a 256`). README lines 18-28 point users
at the GitHub release URL:

```
> **[⬇️ ToshLLM-v0.87.14-beta.1.dmg](https://github.com/SamerKharboush/toshllm/releases/download/v0.87.14-beta.1/ToshLLM-v0.87.14-beta.1.dmg)**
> ([release notes](.../releases/tag/v0.87.14-beta.1) · [checksums](.../v0.87.14-beta.1/checksums.txt))
> **This particular `.dmg` is built for AVX-but-not-AVX2 Intel CPUs** ...
```

So the user-facing beta is the locally built (kernel-less) one. README "Known gaps" states the
gap twice, at lines 227-230 and 237-238:

- "The first launch spends about 143 s compiling Metal kernels. The bundle ships without
  precompiled kernels because the build machine had no Xcode `metal` compiler..."
- "The `.dmg` from this release has no precompiled Metal kernels, because no Xcode `metal`
  compiler was available on the build machine. The engine compiles its own at first launch."

## 6. Caveats

- `gh api repos/SamerKharboush/toshllm/actions/runs/<id>/artifacts` returns HTTP **404** on this
  fork even though the artifacts exist; `gh run download` works. Artifact names/IDs above come
  from the `Publish release` job log instead.
- The metallib arch question is answered *behaviorally* (all 25 load on Intel AMD Metal 2), not
  by parsing GPU-family tables out of the container. Token-level evidence is consistent with
  arch-neutrality: only AIR/GPU-side strings, no host-CPU strings at all.
- The `precompiled 26` count from the script vs 25 shipped files is unresolved; likely one
  duplicated or overwritten name. Cosmetic, but worth confirming if the fingerprint is used to
  gate loading (an extra fingerprint line with no `.metallib` could make the loader look for a
  library that isn't there).