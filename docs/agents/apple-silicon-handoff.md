# Apple Silicon handoff — read this first

You are on an Apple Silicon Mac. This repository is a fork that targets **Intel Macs with
discrete AMD GPUs**. Almost none of its engine work applies to your hardware. This document
tells you what is true, what is already done so you do not redo it, what is still broken, and
exactly what to work on.

Written 2026-10-02 at commit `c3c06be`, version `0.87.14-beta.2`.

---

## 1. What this repo is

ToshLLM is a SwiftUI macOS app that wraps a patched `llama.cpp` to run local LLMs. Upstream is
`engeldlgado/toshllm`; this fork is `SamerKharboush/toshllm`.

Upstream's premise: stock `llama.cpp` produces **corrupted output** on AMD discrete GPUs under
Metal, because AMD GCN reports a 64-wide SIMD group while every Metal kernel assumes 32. This
fork fixes that and then measures everything it claims.

Pinned engine commits:

| engine | commit |
|---|---|
| llama.cpp | `9575389609d6f8437de0b205561a4824d217c409` |
| whisper.cpp | `371b5a7561823ab2bb32142d2751e35e7534727b` (v1.9.3) |
| stable-diffusion.cpp | `2f88688` |

Engine fixes live as a patch series in `patches/<engine>/`, applied in numeric filename order.
`patches/llama/` currently has 123 patches; `image/` 20, `shared-metal/` 7, `diag/` 17,
`whisper/` 2.

---

## 2. Read these, in this order

1. **`README.md`, the "Fork changes" section** — every defect this fork fixed, with measured
   numbers. This is the single densest document.
2. **`CONTEXT.md`** (untracked, at repo root) — the glossary. Terms like *split VRAM budget*,
   *per-device ceiling*, *per-buffer ceiling*, *pp vs tg*, *GCN codegen trust* are used
   precisely and mean what they say there. Do not paraphrase them.
3. **`.scratch/firellama-maxperf/map.md`** — the ticket map and every decision made along the
   way, including the refuted theories. Read the "Decisions so far" section before forming an
   opinion; several plausible ideas are already dead.
4. **`patches/README.md`** — how to add a patch without corrupting the series. Follow it
   exactly.
5. **`docs/agents/issue-tracker.md`** — how tickets are tracked here.

---

## 3. What is already done. Do not redo any of this.

Everything in this section is committed, pushed, measured, and released as `v0.87.14-beta.2`.

### 3.1 The GCN fixes — inert on Apple Silicon, but read them anyway

**Timestep embedding produced wrong tokens (patch 0125).** The Metal kernel's odd-dimension
branch compiled to the wrong arm on GCN, so every row zeroed its successor's first element and
the last row wrote past the end of the destination. Fix: `half_ * 2 < args.dim` instead of
`half_ * 2 < args.dim && tpitg.x == 0`-style guards that took the odd path for even dims.
Backend suite went from one failure at `ERR=0.002926276` to exact.

**Cross-GPU events deadlocked on a layer split (patch 0126).** The destination's wait was
encoded into a *new* command buffer, which queued the copy behind whatever the destination
already had. A destination parked on a long graph could never drain the hand-off that graph was
waiting on. Now bounded by `TOSH_MGPU_XDEV_TIMEOUT_MS` (default 2000 ms); on timeout it drains
both queues, completes the sequence by hand, and falls back.

**`NSMakeRange` overran its buffer (patch 0126).** `NSMakeRange(bid_dst.offs, bid_dst.offs + size)`
passed an *end offset* where a *length* belongs, so the fill ran `offs` bytes past the region
the caller asked for. Now `size`.

**Tensor split refusal (patch 0128).** Some models — the 27B `qwen35` SSM state reshape is one —
cannot be tensor-split at all: `ne[0]=6144` does not divide `ne[0]=9216`. The engine used to
abort with a bare `GGML_ASSERT` after the weights had loaded. It now prints the op and the
dimensions and `exit(86)`; the app catches 86 and relaunches once with `--split-mode layer`. The
saved split-mode setting is deliberately **not** rewritten. `TOSH_TENSOR_SPLIT_STRICT=1`
restores the abort.

### 3.2 Regression tests that exist

- `vendor/llama.cpp/tests/test-metal-memset.cpp` — patch 0127. Five offsets (0, 1024, 3584, 4000,
  2048), registered in `tests/CMakeLists.txt` under `if (GGML_METAL)`. Fails on the pre-0126 form
  with `offset=1024 → 1024 clobbered`, `3584 → 256`, `4000 → 80`.
- App unit tests in `Tests/ToshLLMTests/`.

### 3.3 App fixes

| defect | fix |
|---|---|
| LAN host toggle did nothing | `ToshLLMApp.swift` wrote `localNetworkDiscovery` without pinning `Profile.Pin.discovery`, and `Server.swift` had `pinned == ["model"]` hardcoded. Added `isPinnedDiscovery` / `pinDiscovery()`. |
| Fit abort was silent | Engine keeps going after `--fit` gives up; now surfaces as a `fitNote` on the server card. |
| Multi-GPU off by default | `ServerSettings.defaultMultiGPU = HardwareInfo.detect().gpus.count >= 2`, applied only while the key is unset. Wired at 4 sites: `Server.swift:883`, `SettingsTab`, `DashboardTab`, `Hardware.swift` estimate. |
| `ChatTab.swift` / `DesignSystem/Views.swift` used macOS 26 SDK symbols | `sharedBackgroundVisibility` and `ToolbarSpacer` behind `#if compiler(>=6.2)`, matching the existing `glassEffect` pattern. |
| `VideoGenTab.swift` returned `NSImage` across an actor boundary | New `VideoGenerator.displayFrameData(_:) -> Data?`; `[Data]` crosses, image built on the main actor. |
| `make-app.sh` hard-exited without precompiled metallibs | Three guards downgraded to warnings; engine binaries still bundled unconditionally. |
| ISA variant for pre-AVX2 chips | `TOSH_AVX1=1` in `scripts/build-engines.sh`: AVX+F16C on, AVX2/FMA/BMI2 off. |

### 3.4 A trap that already bit once, recorded so it does not bite twice

The exit-86 fallback for ticket 13 was written **inside** the `if retryWithoutMmproj` braces, so
when that flag was false the `--split-mode layer` rewrite was unreachable. It compiled, the app
logged the right message, and the engine exited 86 twice. The only evidence was the engine's own
`args:` line.

Rule that came out of it: **the startup banner must print the command line actually handed to
the engine**, not the saved settings. `startupBanner(settings:args:)` now takes the real args.
When you add a retry path, add a second `args:` line to the log and check it.

---

## 4. Why this fork does nothing for Apple Silicon

Not a missing slice. Every engine fix is gated on hardware that an Apple GPU cannot report.

| fix | gate | on Apple Silicon |
|---|---|---|
| timestep parity (0125) | GCN/Tahiti miscompile | never compiles to the wrong arm |
| wave64 prefill/decode | `simd_width == 64` | probe returns 32 → off |
| aligned mat-vec reads | `needs_aligned_loads`, derived from `is_wave64` | off |
| AMD flash attention | `TOSH_FA_AMD` **and** `!has_simdgroup_mm` | `has_simdgroup_mm` is true on M1+ → off |
| peer-group allreduce | `peerGroupID != 0` (bridged) | single GPU, no peer group |
| xdev bounded wait (0126) | cross-GPU copies only | no second GPU |

The probe is in `vendor/llama.cpp/ggml/src/ggml-metal/ggml-metal-device.m:1770-1800`. It
compiles a trivial kernel and reads `threadExecutionWidth`:

```
ggml_metal: device 0: <name> (peer group 0, not bridged) probed SIMD-group width = 32 (32 = Apple/AMD RDNA, 64 = AMD GCN/Vega)
```

**On your Mac that line will read `32`.** That single number tells you the entire GCN work is
off. Use it as your first check on any log.

The release DMG is also `x86_64`-only (`lipo -info` on all four bundled binaries), so it will not
even launch on your machine. **Use upstream's release for day-to-day use.** This document is
about what you can fix here, not about what you should install.

---

## 5. Environment reality on this machine vs. yours

| | Intel Mac Pro (where this was built) | Apple Silicon (where you are) |
|---|---|---|
| Xcode | 26.3, installed 2026-10-03 | assume present |
| `swift test` | works (319 tests, 1 skipped) | works |
| `xcrun metal` | works, toolchain downloaded | works |
| CPU ISA | Xeon E5-2697 v2, AVX1 no AVX2 | arm64 |
| Metal simd width | 64 | 32 |
| GPUs | 2× FirePro D700 | 1 |

Two consequences for you specifically:

1. **`swift test` works here and is the cheapest gate you have.** Use it constantly. The
   upstream CI does the same on `macos-26` runners.
2. **You can close the precompiled-kernels gap.** `scripts/build-engines.sh:47-60` downloads the
   Metal toolchain if `xcrun metal` is missing and sets `METAL_PRECOMPILE=1`. On your machine it
   will succeed, so a DMG you build **will** ship `default.metallib` and skip the ~143 s
   first-launch shader compile. See task T4.

---

## 6. Build and test, on your machine

```sh
git clone https://github.com/SamerKharboush/toshllm
cd toshllm
git checkout v0.87.14-beta.2        # or main

# Engines. On arm64 the host arch is the right default.
./scripts/build-engines.sh          # ARCH=arm64 implicitly; ARCH=universal for fat binaries

# Fast gate.
swift test

# App bundle. On your Mac this produces an arm64 .app.
TOSH_NO_BUMP=1 ./make-app.sh
```

Then the engine suite, which is the gate that caught the real defects:

```sh
cd vendor/llama.cpp
./build-static/bin/test-backend-ops -b MTL0          # full run
./build-static/bin/test-backend-ops -b MTL0 -o TIMESTEP_EMBEDDING   # the narrow red loop
./build-static/bin/test-metal-memset                 # the 0127 regression test
```

The narrow red loop first, always. A full suite run takes minutes; `-o TIMESTEP_EMBEDDING` takes
seconds and is what the timestep defect was found with.

Release a DMG:

```sh
./scripts/make-dmg.sh v0.87.15-beta.1     # -> dist/ToshLLM-v0.87.15-beta.1.dmg
cd dist && shasum -a 256 *.dmg > checksums.txt
gh release create v0.87.15-beta.1 --repo SamerKharboush/toshllm \
  --title "..." --notes-file notes.md --draft --prerelease
gh release upload v0.87.15-beta.1 *.dmg checksums.txt --repo SamerKharboush/toshllm --clobber
gh release edit v0.87.15-beta.1 --repo SamerKharboush/toshllm --draft=false --prerelease
```

`make-app.sh` bumps the last version component unless `TOSH_NO_BUMP=1` or `CI=true`. `VERSION` is
the single source of truth and `AboutTab.swift` is rewritten from it.

**CI note:** this fork's GitHub Actions does not fire on push (fork setting). Only
`workflow_dispatch` and tag pushes have been observed to run, and even tag pushes did not fire.
Trigger manually:

```sh
gh workflow run build.yml --repo SamerKharboush/toshllm -f notarize=false
```

---

## 7. Still broken. This is your work list.

Ordered by value. Each has an acceptance test you can actually run.

### T1 — Universal/arm64 build: OUT OF SCOPE by decision, 2026-10-03

The owner has decided this fork targets **Intel x86_64 hardware only**. No arm64 slice will be
built, and no Apple Silicon support will be added. Drop this task.

If that decision is ever reversed, the machinery is unchanged and still there:
`scripts/build-engines.sh` accepts `ARCH=universal` and `make-app.sh` accepts
`TOSH_ARCH=universal`, neither has been run for arm64, and the AVX2 intrinsics in patches `0115`
and `0105` are guarded on `defined(__x86_64__)` / `defined(__AVX2__)` so arm64 should compile to
the generic path. Verify rather than assume. An arm64 slice also needs its own Metal kernels
compiled for it; `ggml_metal_library_precompiled_matches` refuses a library whose source hash
does not match, so a mismatch falls back to compiling rather than loading something wrong.

For day-to-day use on Apple Silicon, upstream's release remains the right answer. Every engine fix
in this fork is an AMD GCN workaround that an Apple GPU switches off by construction.

### T2 — Notarization: DEFERRED by decision, 2026-10-03

The owner does not want this now; it is planned for the point the project is rebranded. Drop this
task until then.

For the record, so nobody re-derives it: the build is ad-hoc signed, so macOS quarantines it and
the user must right-click → Open or run `xattr -dr com.apple.quarantine`. The pipeline is fully
wired in `build.yml` and skips cleanly when the credentials are absent, so turning it on at rebrand
time is a matter of adding the secrets, not writing code. It needs an Apple Developer identity: a
Developer ID certificate as base64 in a CI variable, its passphrase, and the four notary-tool
credentials. The exact variable names are in the `sign` step of `build.yml` — read them from there
rather than guessing, and never write their values into this repo or any commit message. Apple's
notary queue took 66 min on this account's first submission, so budget for it. Do not attempt to
work around signing.

### T3 — LAN fix from a second machine: CONFIRMED by the owner, 2026-10-03

The owner has tested from a second machine and confirms it works. The earlier verification here was
from a second IP on the same host, with the engine bound to `0.0.0.0`: `/health` returned `ok`,
`/v1/models` returned 200, and chat answered coherently at 4.99 tok/s. Cross-machine confirmation
now closes it. Drop this task.

### T4 — Precompiled Metal kernels: DONE on the Intel box, 2026-10-03

Xcode 26.3 and Apple's Metal toolchain are now installed on the Mac Pro
(`xcodebuild -downloadComponent MetalToolchain`, 704.6 MB). `build-engines.sh` now prints
`Metal compiler available — will precompile default.metallib` and produces 25 `.metallib`
files plus a `fingerprint` manifest for the inference engine, and a `default.metallib` for each
of the speech and image engines.

Measured: first launch to listening went from ~143 s to **16 s** on the 14B across both D700s.
Shipped in `v0.87.14-beta.3`. Chat verified coherent, `finish_reason: stop`.

Note the fingerprint check in `ggml_metal_library_precompiled_matches`: a library whose recorded
source hash does not match the sources embedded in the binary is refused and the engine compiles
instead. If you change a `.metal` file, rebuild the engines — do not hand-edit a fingerprint,
and do not "optimize" by relaxing that check.

**Still open for you:** if you build an arm64 slice, its kernels must be compiled too. The
fingerprint is per-source, not per-architecture, but a library built for one GPU family will not
run on another; confirm the arm64 bundle loads rather than silently falling back.

### T5 — Numerical A/B for the `NSMakeRange` fix

**The bug.** `ggml-metal-device.m:3502`, `ggml_metal_buffer_memset_tensor`:

```objc
bid_dst.offs += offset;
[encoder fillBuffer:bid_dst.metal range:NSMakeRange(bid_dst.offs, bid_dst.offs + size) value:value];
```

`NSRange` is `(location, length)`. The length argument was `offs + size`, the *end offset*, so the
fill ran `offs` bytes past the region the caller asked for — into whatever tensor the allocator
placed next in the same buffer. Patch 0126 changes it to `size`.

**Who can trigger it.** Exactly two callers exist in the tree:

| caller | offset | reachable? |
|---|---|---|
| `ggml.c:7813` — `memset(tensor, 0, 0, nbytes)` | always 0 | no: with `offs = 0`, `offs + size == size`, so the bug is invisible |
| `llama-kv-cache-dsv4.cpp:38` — `memset(tensor, 0, stream*stream_size, stream_size)` | non-zero | **yes** |

So the answer to "can this fire in production" is: only through the DSV4 KV cache. That is a
static argument and needs no run to make.

**What is still missing.** No end-to-end numerical comparison, because no DSV4 model has been run
here.

**The test.** One DSV4 model, two engines, same seed and prompt:

- engine with patch 0126 → answer A
- engine with the fill reverted to `offs + size` → answer B
- A and B must be identical

**What failure looks like.** For stream `n` the memset writes `n*stream_size` extra bytes starting
at `n*stream_size + stream_size`, landing at the head of stream `n+1`'s region. `dsv4_clear_tensor_stream`
is called per stream per layer on sequence removal (`llama-kv-cache-dsv4.cpp:1013-1014`, and
`:1742` for `seq_rm` with `data`), so several streams get cleared per turn and they
cross-contaminate. It would surface as wrong output after a conversation turn, or as a cache that
degrades over a long session — never as a crash, which is why it survived upstream.

**Why it is worth doing.** DSV4 is recent upstream code, so real models exist that reach it. If A
and B differ, that is a live upstream bug affecting everyone on Metal, not just this fork. If they
match, the fix is confirmed harmless and patch 0126 can go upstream with evidence rather than by
inspection.

**Acceptance:** A recorded, with both answers and the model named. Either outcome is a real
answer. Silence is not.

### T6 — Clean up stale state

Minor, but it misleads the next reader:

- **Done 2026-10-03.** The map's "Blocked" section no longer claims the app fails to compile; it
  records that `swift build` is green and why `swift test` could not previously run.

**Do not delete `patches/llama/0114-server-agent-clients-get-what-they-send.patch`.** It looks
like a stray diagnostic file with a descriptive name and no number-series sibling, but it is
tracked and it is part of the applied series — `build-engines.sh` picks up every `*.patch` in the
directory. Removing it drops a real fix from the build. Check `git ls-files` before deleting
anything under `patches/`.
- `CONTEXT.md` is intentionally untracked. Leave it.
- PR #1 was closed as superseded. Nothing to do.

---

## 8. Working rules in this repo

These are not style preferences. Each one exists because breaking it produced a real bug.

**Measure, never argue.** A claim without a number did not happen. The whole fork is built on
this: `README.md` cites 21.25 / 5.08 tok/s, not "faster".

**Build the red loop before the theory.** One command, deterministic, fast, agent-runnable, and
capable of failing. The timestep defect was found by writing a byte probe, not by reasoning about
Metal's compiler.

**A sentinel mismatch means a write landed outside its tensor.** The magnitude of the error does
not localise it. This cost hours once.

**Do not theorise from an error value.** `precise::` was a plausible, tidy, wrong theory about the
timestep defect. Byte-level probing found the real one in a single run. `map.md` records it under
"refuted" so nobody walks it again.

**Reproduce before fixing.** Patch 0114 once failed to apply because it carried deleted lines as
context. Reproduce against a pristine worktree of the pinned commit, every time.

**One patch per change, `-U8`, numeric order, never reuse a number.** At `-U8` four of the base
patches regenerate byte for byte; narrower rewrites every hunk header and a hunk can land in the
wrong kernel while the build still exits 0. Before regenerating, check the vendor tree matches
what the series touches — otherwise you will overwrite a live experiment. Then verify the round
trip: apply the whole series to a pristine worktree of `9575389609d6` and diff. No source file may
differ.

**`build-engines.sh` resets the vendor tree and re-applies the patch files.** Working-tree edits
there are discarded. Regenerate patches *before* building, never after.

**Do not remove the expected-reject check in `patches/image/0002`.** Four hunks cannot land on
the image engine's older ggml. The script asserts which hunks are expected to reject and stops
rather than shipping a backend missing one.

**Gate every claim.** `test-backend-ops` full green plus a smoke bench for a kernel-local fix. A
change to a shared helper owes the full tensor-events baseline. `map.md` Q2 records the reasoning:
a kernel-local fix cannot regress a path it is not on.

**State gaps explicitly in README and changelog.** The "Known gaps" section is load-bearing, not
an apology. Notarization, the 143 s compile, the untested LAN path, the missing Apple Silicon
slice — all of it is written down.

---

## 9. Definition of done for any change here

1. A red loop exists and fails without the fix.
2. The fix makes it pass.
3. The full `test-backend-ops` suite is green. `test-metal-ops` count should read `10701/10701`.
4. `swift test` is green.
5. A benchmark or a correctness measurement is recorded, in the commit message, with the command
   that produced it.
6. `README.md` and `CHANGELOG.md` updated if behaviour or defaults changed.
7. If an engine change: patch regenerated at `-U8`, series round-trip verified against a pristine
   worktree.
8. Commit message says what was broken, what the fix is, and what was measured. No adjectives
   without numbers.
