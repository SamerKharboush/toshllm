# Metal toolchain facts for the Intel Mac Pro 2013 target

Research date: 2026-10-02. Target: Mac Pro 2013 (Xeon E5-2697 v2, x86_64), macOS 15.8 (24H23) via
OCLP, 2x AMD FirePro D700 exposed as `MTLGPUFamilyCommon3`, no Xcode (Command Line Tools only,
SDK 15.5, Swift 6.1.2), `xcrun metal` and `xcrun -f metallib` both fail.

Build invocation under study (`scripts/build-engines.sh`):

```
xcrun metal -O3 -mmacosx-version-min=14.0 -std=metal3.1 \
  -DGGML_METAL_EMBED_LIBRARY -DGGML_METAL_HAS_BF16 \
  -I ggml/src -I ggml/src/ggml-metal -c <src>.metal -o <name>.air
xcrun metallib <name>.air -o <name>.metallib
```

One `.metallib` per source file, loaded at runtime with `-[MTLDevice newLibraryWithURL:error:]`,
with runtime source compilation as the fallback.

## What this means for us

- **The newest Xcode that can be installed on the target box is Xcode 26.3 (17C529).** Xcode 26.4+
  requires macOS Tahoe 26.2 and Xcode 27 requires macOS Tahoe 26.6, so they are out. Intel slices
  are still published for Xcode 26.0–26.6 (`Xcode_26.x_Universal.xip`); Xcode 27 is published as a
  single download with no Apple-silicon-only sibling, so Intel support looks dropped there. Xcode
  16.4 also installs fine (needs macOS 15.3+) and is the cheapest path because it still bundles the
  Metal Toolchain.
- **A metallib built on an Apple Silicon host is not host-architecture-specific.** `.air` is LLVM
  bitcode carrying a target triple like `air64-apple-macosx14.0.0`; `air`/`air64` is pointer width,
  not x86 vs ARM. So the `macos-26` (arm64) runner can emit kernels the Intel box loads, and there
  is no need — and no documented way — to lipo two `.air` sets into one metallib.
- **The real gating is OS version and GPU family, not CPU arch.** The deployment version lives in
  the AIR target triple that `-mmacosx-version-min=14.0` sets, so a macOS 26 SDK compile with that
  flag still says "14.0" and should load on 15.8. Forgetting the flag is what breaks older systems.
- **Free Intel CI runners now exist and are labelled `-intel`.** `macos-15-intel` (macOS 15.7.9,
  Xcode 16.0–16.4 default, plus 26.0.1–26.3) and `macos-26-intel` (macOS 26.6.1, Xcode 26.0.1–26.6)
  are both in GitHub's *standard runners for public repositories* table. Note that plain
  `macos-15` and `macos-26` are **arm64** now, as is `macos-latest`; the project's `runs-on: macos-26`
  is building on Apple Silicon.
- **`xcodebuild` cannot run at all without an Xcode app**, verified on this machine. So
  `xcodebuild -downloadComponent MetalToolchain` is unreachable from Command Line Tools alone, and
  the Metal Toolchain has no standalone `.pkg` — it is a `.dmg` component imported *into* Xcode.
  Installing an Xcode (16.4 or 26.3) is a prerequisite for any local or CI metallib build.

---

## 1. Xcode on macOS 15.8, x86_64, Intel

Apple's SDK and system requirements table gives the minimum macOS per release. Combined with
`xcodereleases.com`, which records the exact build numbers and whether a Universal (Intel) download
exists:

| Xcode | Build | Min macOS | Max macOS | Intel download published? |
| --- | --- | --- | --- | --- |
| 16.2 | 16C5032a | 14.5 | 15.x | single `Xcode_16.2.xip` (universal) |
| 16.3 | 16E140 | 15.2 | 15.x | yes |
| 16.4 | 16F6 | 15.3 | 26.1.x | yes |
| 26.0 – 26.0.1 | 17A324 / 17A400 | **15.6** | 26.x | yes — `Xcode_26.x_Universal.xip` **and** `Xcode_26.x_Apple_silicon.xip` |
| 26.1 – 26.1.1 | 17B55 / 17B100 | 15.6 | 26.x | yes, both variants |
| 26.2 | 17C52 | 15.6 | 26.x | yes, both variants |
| 26.3 | 17C529 | 15.6 | 26.x | yes, both variants |
| 26.4 – 26.6 | 17E192…17F113 | **26.2** | 26.x | yes, both variants |
| 27 / 27.1 / 27.2 beta | 27A266a… | **26.6** | 27.x | single download only — no `_Apple_silicon` sibling, no `_Universal` |

macOS 15.8 clears the 15.6 floor, so Xcode 26.3 is the ceiling. Xcode 26.4+ and all of Xcode 27 are
unreachable on this box because they need macOS Tahoe 26.2/26.6, and macOS 26 cannot run on a Mac Pro
2013 at all (Tahoe requires MacBook Pro 2016+/iMac 2017+/Mac Pro 2017+), while macOS 27 is
Apple-silicon-only.

Intel support was **not** dropped for the 26.x line: Apple publishes a separate `_Apple_silicon.xip`
for 26.0 through 26.6, which only makes sense if the default `_Universal.xip` carries an x86_64 slice.
Apple's own component docs confirm the concept ("Xcode downloads a universal variant for Intel-based
Mac computers"). Community reports corroborate that Xcode 26 installs and runs on Intel Macs on
Sequoia 15.6+, including a 2015 MacBook Pro and an Intel MacBook 2019 under macOS Tahoe. I could not
test any of this here — this box has no Xcode.

- Confidence: **high** on the version/OS matrix (Apple's table is authoritative and matches
  `xcodereleases`); **medium** on "the x86_64 slice actually launches and works", which rests on the
  published Universal filenames plus community reports rather than a first-party statement.
- Citations: https://developer.apple.com/xcode/system-requirements/ ,
  https://xcodereleases.com/ , https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes
  (the Xcode 26 release notes state "requires a Mac running macOS Sequoia 15.6 or later"),
  https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components

## 2. Standalone Metal toolchain

`xcodebuild -downloadComponent MetalToolchain` requires an Xcode app, and this is not a theoretical
constraint — verified directly on the target machine:

```
$ xcodebuild -version
xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory
'/Library/Developer/CommandLineTools' is a command line tools instance
$ xcodebuild -showComponent metalToolchain     # same error
```

The shim at `/usr/bin/xcodebuild` refuses to run against a Command Line Tools developer dir, so the
download path is unreachable until an Xcode is installed. This matches what `CONTEXT.md` already
records.

The Metal Toolchain is not distributed as a standalone `.pkg`. Apple's documented flow exports it as
a **dmg** and imports it *into* a selected Xcode:

```
xcodebuild -downloadComponent metalToolchain -exportPath ~/Downloads
xcodebuild -importComponent metalToolchain ~/Downloads/metalToolchain.dmg
```

and the install section begins "First, select the version of Xcode you want to use with
`xcode-select -s <path-to-Xcode>` … run `xcodebuild -runFirstLaunch`". Apple's Metal developer tools
page says "Download Xcode to start using the full suite of Metal developer tools." An Apple Developer
Forum thread titled "Where can I get the standalone Metal Toolchain for Xcode 26?" resolves to
`xcodebuild -downloadComponent metalToolchain` landing in `/System/Library/AssetsV2/…`, i.e. still
driven by Xcode. There is no Apple-hosted per-OS Metal Toolchain package.

One more wrinkle: **as of Xcode 26 the Metal Toolchain is no longer bundled with Xcode at all**, so
even a successful `xcodes install 26.x` leaves you without `metal`. GitHub's runner-images tracker has
this open with the literal error `cannot execute tool 'metal' due to missing Metal Toolchain; use:
xcodebuild -downloadComponent MetalToolchain`, affecting macOS 13/14/15/26 images. Conversely,
Xcode 16.x and earlier ship the Metal Toolchain in the box, which is why the `macos-15-intel` image's
default Xcode 16.4 works with no extra step.

`xcodes` (the CLI, `XcodesOrg/xcodes`) installs and switches Xcode versions only. Its README documents
`install`, `select`, `list`, `uninstall`, and the `ExperimentalUnxip` path; there is no
component/toolchain subcommand and no mention of Metal. It is a solution for *getting an Xcode onto
the box*, not for getting a `metal` binary by itself.

Each Metal Toolchain build is versioned to a specific Xcode build (visible in
`xcodebuild -showComponent metalToolchain`), so a toolchain from one Xcode cannot be assumed to work
with another.

- Confidence: **high** for the CLT limitation (measured locally), **high** for "no standalone pkg,
  dmg imported into Xcode" (Apple's own docs), **high** for Xcode-26 de-bundling (runner-images +
  multiple independent reports), **high** for `xcodes` scope.
- Citations: https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components
  (section "Download and install the Metal Toolchain"),
  https://github.com/actions/runner-images/issues/13014 ,
  https://www.polpiella.dev/metal-toolchain-ci-cd ,
  https://github.com/XcodesOrg/xcodes ,
  https://developer.apple.com/metal/tools/ ,
  https://developer.apple.com/forums/thread/803174

## 3. Cross-architecture metallib

### 3a. What the Metal compiler targets, and what `-target` means

The default target of `xcrun metal` is **not** the host CPU. `.air` files are ordinary LLVM bitcode
(verified by third-party reverse engineering: `file x.air` → `LLVM bitcode, wrapper`), and the
module header carries a **target triple** of the form `air64-apple-macosx14.0.0`. `air` vs `air64` is
the pointer width of the GPU address space, not x86_64 vs arm64. A shader compiled on an M-series Mac
and a shader compiled on the Mac Pro therefore produce structurally identical AIR for the same
`-std` and deployment target.

`-target` is inherited from the clang driver (the Metal compiler is a modified clang), documented as
"Generate code for the given target". What the MSL specification actually documents is different and
more useful: §1.6.10 lists the `-std=` values, and §1.6.15 lists `-arch <architecture>` and
`-gpu-family <gpu family name>`. Notably the specification never mentions `-target`, `-mmacosx-version-min`
or `-mtargetos` — those are clang-driver-level deployment flags that the driver maps onto the triple.
`-mmacosx-version-min=` and `-mtargetos=` are both real clang options ("Set the deployment target to
be the specified OS and OS version").

So the practical answer to "how do I target the Intel box" is: **do not use `-target` at all.** Pin the
OS with `-mmacosx-version-min=14.0` and the language with `-std=metal3.1`, exactly as the build script
already does. I could not obtain the compiler's `--help` output, so I cannot enumerate the complete
accepted `-target` vocabulary; the specific names in the question (`air`, `air64`, `macos`,
`macosx_x86_64`, `macos-metal`) look like a mix of triple components and `-std` aliases —
`macos-metal*` values are definitively `-std` values per §1.6.10, not `-target` values.

- Confidence: **high** that host CPU architecture does not affect the default target (AIR triple
  evidence), **medium** on the exact `-target` vocabulary (unverified, no `metal --help` available).
- Citations: https://worthdoingbadly.com/metalbitcode/ (metallib/AIR reverse engineering),
  https://medium.com/@samuliak/breaking-down-metals-intermediate-representation-format-41827022489c
  (`target triple = "air64-apple-macosx14.0.0"`),
  https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf §1.6.10 and §1.6.15,
  https://clang.llvm.org/docs/ClangCommandLineReference.html

### 3b. Can `metallib` link `.air` files from different targets into one multi-slice metallib?

Almost certainly not, and — importantly — **you do not need it.** A metallib is not a fat binary in
the Mach-O sense. Its container format (magic `MTLB`) is a header of per-entry-point tags (`NAME`,
`TYPE`, `HASH`, `MDSZ`, `OFFT`, `VERS`) followed by one LLVM bitcode blob per entry point. There is no
architecture-slice table anywhere in the format. Apple documents `metallib` purely as a linker step
("Use the `metallib` tool to build a Metal `.metallib` library file from IR `.air` files or from
archive `.metalar` files"), with no notion of architecture slices. Since AIR is already
architecture-neutral, "one metallib that covers both Intel and Apple Silicon" is simply the normal
case, and the existing one-metallib-per-file layout is not a blocker.

Because the engine hard-requires `kernels/<name>.metallib` one file at a time, the correct mental
model is: **one AIR target triple per metallib, chosen so that both x86_64 and arm64 macOS ≥14
consumers can load it.** That is what `-mmacosx-version-min=14.0 -std=metal3.1` already produces.

I found no Apple documentation and no reliable third-party report on linking `.air` files built for
*different* targets into a single metallib, in either direction.

- Confidence: **medium-high** that multi-target linking is unnecessary and probably unsupported;
  **low** on what `metallib` actually does if fed mixed-target inputs (it may silently accept them,
  producing a library whose per-function blobs disagree).
- Citations: https://developer.apple.com/library/archive/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/Dev-Technique/Dev-Technique.html
  (the `metal` → `metal-ar` → `metallib` pipeline),
  https://worthdoingbadly.com/metalbitcode/ (MTLB container layout)

### 3c. How Metal decides which GPU-family variants to emit

The documented knob is `-gpu-family <gpu family name>`: "Specify the architectures associated with
the MTLGPUFamily to build for. See MTLGPUFamily in Metal API for the list of available families."
That is the only per-family control Apple documents.

The concerning part is what the *current* Feature Set Tables contain. The Metal Feature Set Tables PDF
as published on Apple's site (dated May 21, 2026) lists **only Apple-family GPUs** — A8 through M5 —
under "Metal GPUs". There is no `Common1/2/3` and no `Mac1/Mac2` column anywhere in the document. That
is consistent with macOS Tahoe 26 dropping Intel Macs: Apple stopped publishing feature tables for
families the current OS cannot reach.

However, the SDK still *knows* those families: `MTLGPUFamily` still enumerates `common1`, `common2`,
`common3`, `mac1`, `mac2`, and Apple's availability metadata for `MTLGPUFamily.common3` reads
`macOS: 10.15.0 - 27.0.0` — i.e. the constant is still declared valid through macOS 27. So the
enumerators survive in the SDK; what is uncertain is whether the macOS 26 SDK's `metal` compiler still
*emits* Common3 code by default for a `-std=metal3.1 -mmacosx-version-min=14.0` macOS target.

The project has direct empirical reason to care: ggml's own `ggml-metal-device.m` probes
`supportsFamily:` across `MTLGPUFamilyCommon1+5` down to `Common1` under `#if TARGET_CPU_X86_64`, so
ggml expects Common-family variants to be present.

I could not verify default GPU-family emission for any `-target`, with or without `-gpu-family`, on
any toolchain. This is the single largest unverified risk in this document.

- Confidence: **high** on the existence and meaning of `-gpu-family`; **high** that the current
  Feature Set Tables omit Common/Mac families; **medium** that `common3` remains a valid declared
  family in the SDK; **low/unknown** on actual default emission from the macOS 26 SDK compiler.
- Citations: https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf ,
  https://developer.apple.com/documentation/metal/mtlgpufamily ,
  https://developer.apple.com/documentation/metal/mtlgpufamily/common3 ,
  https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf §1.6.15

## 4. OS version gating

The deployment target is encoded in the AIR module's **target triple**, e.g.
`air64-apple-macosx14.0.0`. That triple is what `-mmacosx-version-min=14.0` (or the equivalent
`-mtargetos=macos14.0`) sets. So a metallib compiled with the macOS 26 SDK but
`-mmacosx-version-min=14.0` will carry `…macosx14.0.0`, and the 15.8 driver has no reason to refuse
it on OS grounds. Conversely, a metallib compiled *without* the flag on a macOS 26 SDK picks up the
SDK's own version (26.x) and older systems reject it.

The concrete failure signature people hit is `MTLLibraryErrorDomain`. Documented/observed codes:

- `Code=1 "MTLLibrary is not formatted as a MetalLib file."` — the file is not a real metallib. A
  common cause: you ran `metal-ar` and handed its `.metalar` archive to `newLibraryWithURL:`.
- `Code=1 "This library format is not supported on this device."` — a metallib that stops parsing
  after an OS upgrade, i.e. a toolchain/OS mismatch rather than a version-min one.
- `Code=3` — used by the runtime source-compile path for actual shader compile errors (this is how
  ggml surfaces "unknown type name 'block_q4_0'" when a precompiled library is missing types).

On the phrase you asked about: I found **no** report of the literal dyld-style string "Library not
loaded: built for newer macOS" for a Metal library. What does exist is the same class of failure for
the *binaries* around the metallib, and those are well documented:

- llama.cpp issue #26370: prebuilt binaries failing on macOS 15 with
  `dyld[...]: Symbol not found: _posix_spawn_file_actions_addchdir … (built for macOS 26.0 which is
  newer than running OS)`.
- llama.cpp issue #11071: a cascade of
  `ld: warning: object file (...) was built for newer 'macOS' version (14.7) than being linked (14.0)`.

Both are the deployment-target flag not reaching the C/C++ link, not a Metal problem — but they are
the same hazard class, and the project's `DEPLOYMENT_TARGET="14.0"` / `-DCMAKE_OSX_DEPLOYMENT_TARGET`
already guard the C side. The Metal side is guarded by `-mmacosx-version-min=14.0`.

- Confidence: **medium-high** that the triple is the carrier and the flag controls it; **high** that
  `-mmacosx-version-min=14.0` produces a 14.0 triple; **low** on the exact runtime rejection path for
  a too-new triple, which I have no direct report of.
- Citations: https://medium.com/@samuliak/breaking-down-metals-intermediate-representation-format-41827022489c
  (triple in AIR header),
  https://developer.apple.com/documentation/metal/mtllibraryerrordomain ,
  https://github.com/ggml-org/llama.cpp/issues/26370 ,
  https://github.com/ggml-org/llama.cpp/issues/11071 ,
  https://github.com/tinygrad/tinygrad/issues/2226

## 5. GPU-family gating on a Common3-only device

`MTLGPUFamily.common3` is still a declared family with availability `macOS: 10.15.0 - 27.0.0`, and
Apple's documented way to test a device is `[device supportsFamily:MTLGPUFamily.common3]`. A metallib
is bitcode, so the *driver* performs the family-specific lowering at load/dispatch time; if the AIR
contains no variant for any family the device supports, there is nothing the compiler can emit.

Where the failure lands — `newLibraryWithURL:` vs `newFunctionWithName:` — I could not determine from
documentation. Reading the format: a metallib with no matching family is still a structurally valid
`MTLB` container with well-formed bitcode, so the most likely behaviour is that `newLibraryWithURL:`
**succeeds** and the failure surfaces later, at function or pipeline-state creation, as an
`MTLLibraryErrorDomain`/`MTLFunction` error. The counter-evidence is the iOS 13 report where the error
text is "This library format is not supported on this device", phrased at library granularity — which
suggests a load-time rejection is at least possible.

Practical consequence for this project either way: the engine already falls back to runtime source
compilation when `newLibraryWithURL:` fails, but a failure deferred to `newFunctionWithName:` would
**not** be caught by that fallback. That asymmetry is worth designing around — worth verifying
empirically once one metallib exists.

- Confidence: **high** that `common3` remains declared in the SDK and that `supportsFamily:` is the
  documented check; **low** on load-time vs function-time failure.
- Citations: https://developer.apple.com/documentation/metal/mtlgpufamily/common3 ,
  https://developer.apple.com/documentation/metal/mtlgpufamily ,
  https://stackoverflow.com/questions/56884203/metallib-in-ios-13 (SO: `Code=1 "This library format
  is not supported on this device"`; note: direct fetch was blocked, content is from the search index)

## 6. Practical alternatives to a local Xcode

Listed **easiest first**, i.e. increasing effort.

### 6a. GitHub Actions Intel runners — the clean answer

GitHub's standard-runner table lists, for both public and private repositories:

| Label | Arch | CPUs | macOS | Xcodes on the image |
| --- | --- | --- | --- | --- |
| `macos-15-intel` | Intel | 4 | 15.7.9 (24G830) | 26.3, 26.2, 26.1.1, 26.0.1, **16.4 (default)**, 16.3, 16.2, 16.1, 16.0 |
| `macos-26-intel` | Intel | 4 | 26.6.1 (25G76) | 26.6 (default), 26.5, 26.4.1, 26.3, 26.2, 26.1.1, 26.0.1 |
| `macos-latest` | arm64 (M1) | 3 | 26.6.2 | 26.6 default … |
| `macos-15` | arm64 | 3 | 15.7.9 | 26.3 … 16.4 (default) … |
| `macos-26` | arm64 | 3 | 26.6.2 | 26.6 default … |
| `xcode-27` | arm64 | 3 | — | Xcode 27 (public preview) |

Both images also preinstall the `Xcodes` CLI (2.0.3), so switching Xcodes needs no `sudo`.

The critical, plan-changing detail: **`macos-15` and `macos-26` are arm64 now.** The project's
`.github/workflows/build.yml` uses `runs-on: macos-26`, which is an Apple Silicon runner. That is fine
for the *binaries* (they are cross-compiled with `ARCH=x86_64`) and, per §3a, fine for the metallib
too — but it means nobody is currently exercising the Intel path in CI.

Two concrete options:

1. **`macos-15-intel` with the default Xcode 16.4.** No Metal Toolchain download at all (Xcode 16
   bundles it), a macOS 15 SDK, and an Intel host — so the metallib is built in an environment whose
   OS generation matches the target. Lowest risk. `-std=metal3.1` is supported by Xcode 16.4 (MSL 3.1
   arrived with macOS 14 / Xcode 15).
2. **`macos-26-intel` with Xcode 26.x + one component download:**
   `xcodebuild -downloadComponent metalToolchain` then
   `xcodebuild -importComponent metalToolchain -exportPath …` per Apple's documented flow. Newest
   compiler, but a macOS 26 SDK emitting code for a macOS 15 driver.

On the token: a normal user token with `repo` + `workflow` can dispatch workflows on a fork via
`workflow_dispatch`, and `CONTEXT.md` already records that dispatch works where push does not. So a
dispatch-only CI job is reachable today.

- Confidence: **high** for the label/arch/Xcode tables (read directly from the current image READMEs and
  GitHub's runner docs).
- Citations: https://docs.github.com/en/actions/reference/runners/github-hosted-runners ,
  https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md (Intel) and
  `…/macos-15-arm64-Readme.md` (arm64), `…/macos-26-Readme.md` (Intel) and
  `…/macos-26-arm64-Readme.md` (arm64)

### 6b. `-std=metal3.1` availability and fallbacks

`-std=metal3.1` means "language revision 3.1", which per the MSL specification targets **iOS 17,
macOS 14**, tvOS 17, visionOS 1 — and `MTLLanguageVersion.version3_1` confirms availability
`macOS: 14.0.0 -`. The mapping is:

| `-std=` | OS floor | Introduced with |
| --- | --- | --- |
| `metal3.0` | macOS 13 / iOS 16 | Xcode 15 |
| `metal3.1` | **macOS 14** / iOS 17 | Xcode 15 (Xcode 15.3 release notes) |
| `metal3.2` | macOS 15 / iOS 18 | Xcode 16 — "Only Apple silicon supports new features in language standard 3.2 and above" |
| `metal4.0` | macOS 26 / iOS 26 | Xcode 26 |
| `metal4.1` | macOS 27 / iOS 27 | Xcode 27 |

Every Xcode on every runner image listed in 6a supports `-std=metal3.1`, so **no fallback is needed**
on any available runner. If one were ever needed, `-std=metal3.0` is accepted by the same compilers
and would only *lower* the language floor to macOS 13 — harmless for a 14.0 deployment target, and it
would not change GPU-family coverage. `-std=metal2.4` would also be accepted but is a real downgrade:
it loses the unified-language mode that `-std=metal3.0`+ enables, and the sources are written for 3.x.

Note the deliberate choice of 3.1 over 3.2 in the current build: MSL 3.2 and above add features that
**only Apple silicon supports**, so 3.1 is the correct ceiling for a Common3 target.

- Confidence: **high** on the version→OS mapping (Apple's spec table plus `MTLLanguageVersion`
  availability metadata); **medium** on the exact Xcode release that first accepted `-std=metal3.1`
  (inferred from the macOS 14 SDK shipping in Xcode 15.x, not stated verbatim by Apple).
- Citations: https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf §1.6.10,
  https://developer.apple.com/documentation/metal/mtllanguageversion/version3_1 ,
  https://developer.apple.com/documentation/metal/mtllanguageversion/version3_2

### 6c. The `macos-26` runner label

`macos-26` is **arm64** (Apple silicon, M1-class, 3 CPUs, 7 GB), running macOS 26.6.2 (25G83), image
`20260907.0351.1`, with Xcode **26.6 as default** and 26.0.1–26.6 installed. `macos-latest` resolves
to the same arm64 macOS 26 image. The Intel counterpart is `macos-26-intel`. This answers §1's question
about macOS 26 too: GitHub's own Intel macOS 26 image carries Xcode 26.0.1–26.6 but not 16.x, whereas
their macOS 15 image carries both generations.

- Confidence: **high** (read from the image READMEs; the arm64 image is identifiable by
  `JAVA_HOME_*_arm64`, `/opt/homebrew`, `chromedriver-mac-arm64`).
- Citations: https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md ,
  https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md

### 6d. Compiling Metal on Linux — not viable

**No.** Apple's `metal` and `metallib` compiler drivers are closed-source binaries shipped only inside
Xcode's Metal Toolchain. In mainline `llvm-project` there is no Metal frontend: `clang/lib/Sema/SemaMetal.cpp`,
`clang/include/clang/Sema/SemaMetal.h` and `clang/tools/metal-driver` all return 404, and a recursive
tree walk of the repository finds no Metal shading-language sources. The `metal` tool is a *modified*
clang that Apple has not upstreamed. Darling's build tracker states it plainly: "Metal shader compilers
aren't open sourced so can't recompile this part of the build stack," and the NixOS Discourse thread
on packaging the Metal compiler says the proprietary CLI tools `metal` and `metallib` "are closed
source and only bundled with Xcode, not even with the Command Line Tools."

There are projects that generate AIR without Apple's compiler — libfloor uses a *patched* LLVM, and
LLAIR wraps the Xcode tools — but neither reproduces the GPU-family variant set and container format
that Apple's driver requires to load a metallib on real hardware. Treat Linux metallib generation as a
dead end for this project.

- Confidence: **high** that there is no open-source path; **high** on the primary evidence (404s
  against mainline llvm-project, Darling and NixOS maintainers).
- Citations: https://github.com/darlinghq/darling/issues/326 ,
  https://discourse.nixos.org/t/using-metal-shader-compiler-inside-derivation/38773 ,
  https://stackoverflow.com/questions/49810845/metal-shading-language-ir-format ,
  `raw.githubusercontent.com/llvm/llvm-project/main/clang/lib/Sema/SemaMetal.cpp` (404)

## 7. Pitfall list — what makes a precompiled metallib silently unusable

Ordered by how quietly it fails.

1. **Assuming the metallib needs an x86_64 slice.** It does not (§3a). If someone "fixes" a
   non-loading metallib by switching runners to an Intel image, they fix nothing and add a maintenance
   burden. The real knobs are OS version and GPU family.
2. **No Common-family variant in the metallib.** The macOS 26 SDK's Feature Set Tables no longer list
   Common1/2/3 or Mac1/2 at all. If the macOS 26 `metal` compiler follows that and stops emitting
   Common3 code, a Common3-only FirePro D700 has nothing to run — and per §5 the failure may appear at
   `newFunctionWithName`, which the engine's `newLibraryWithURL` fallback would **not** catch.
   Mitigations to consider: build with an older SDK (macOS 15 SDK on `macos-15-intel`), and/or pass
   `-gpu-family common3` explicitly, and/or add a post-load `newFunctionWithName` probe before trusting
   the library.
3. **Deployment target not reaching the AIR triple.** Omitting `-mmacosx-version-min=14.0` on a macOS
   26 SDK stamps 26.x into the triple. Symptom class documented in llama.cpp #26370 (`built for macOS
   26.0 which is newer than running OS`) and #11071 (`built for newer 'macOS' version (14.7) than
   being linked (14.0)`). The same hazard exists for the C/C++ side via
   `-DCMAKE_OSX_DEPLOYMENT_TARGET`, which the script already sets.
4. **`-D` define drift between the precompile and the engine.** The build passes
   `-DGGML_METAL_EMBED_LIBRARY -DGGML_METAL_HAS_BF16`. `GGML_METAL_HAS_BF16` changes which types and
   kernels exist; a metallib compiled with different defines than the runtime source-compile path uses
   produces a library whose ABI does not match what the host code expects. Any change to the define
   set must invalidate the precompiled kernels, not just the C++ objects.
5. **Shader-language / SDK version skew, and it bites as *source* breakage.** MLX is the cautionary
   tale: Metal Toolchain 32023 (Xcode 26.4) moved `vec` into namespace `metal` and stopped
   transitively including `<metal_bfloat>`, so previously-valid ggml-style code
   (`vec<T,N>`, `bfloat16_t`) stopped compiling outright. A newer toolchain is not automatically
   "more compatible" — it is a different language surface. Building with the macOS 15 SDK / Xcode 16.4
   avoids this class entirely.
6. **Fingerprint mismatch with the embedded sources.** The build writes `kernels/fingerprint` as
   `sha256` per source. If the engine uses that to decide whether a precompiled library is still
   valid, then editing a `.metal` source without regenerating the fingerprint (or vice versa) makes the
   library stale-but-loadable — the worst failure mode, because nothing errors.
7. **Wrong file handed to `newLibraryWithURL:`.** `Code=1 "MTLLibrary is not formatted as a MetalLib
   file."` is what you get from a `.metalar` archive (the `metal-ar` output) or a truncated/zero-byte
   file. Worth a size/`file` sanity check in the CI job that produces the artifacts.
8. **Mixing `.air` inputs from different toolchains into one metallib.** Untested and undocumented. The
   `VERS` tag per entry point records a bitcode/AIR version, so cross-version input is at best fragile.
   Keep every `.air` in a given metallib from one `metal` invocation.
9. **One metallib per source file means N compilations.** The sources share helper names so they
   cannot be linked together; that is a real constraint of the current design, but note it is a
   *naming* constraint, not a technical one — the comment in `build-engines.sh` says as much. If the
   one-file-per-metallib shape becomes painful, the escape hatch is prefixing/renaming helpers at
   embed time (the same trick ggml's CMake already uses to concatenate headers), which would allow one
   metallib for everything. Not needed today; worth remembering.
10. **`xcodebuild` under Command Line Tools.** Already known (`CONTEXT.md`), but it silently disables
    the one command that would have fixed the toolchain. Any CI job that reaches for
    `xcodebuild -downloadComponent` must first assert an Xcode app is present.
11. **Assuming the fallback always engages.** The engine falls back when `newLibraryWithURL:` fails. It
    does not necessarily fall back when a *function* is missing from an otherwise-loadable library
    (pitfall 2). "We have a fallback" is not the same as "the fallback covers this".

---

## What I could NOT verify

- **Whether the macOS 26 SDK's `metal` compiler still emits `MTLGPUFamilyCommon3` code by default.**
  This is the crux of §3c and §5 and it is unverifiable without a macOS 26 toolchain to run. The
  Feature Set Tables dropping Common/Mac families is suggestive but not conclusive; the SDK still
  declares `common3` as valid through macOS 27. **Single biggest open risk.**
- **The complete set of `-target` values the Metal compiler accepts**, and what each means. I have no
  access to `metal --help` on this box, no Apple doc listing `-target`, and could not find a
  third-party dump of the help text. The names in the question mix triple components (`air`, `air64`)
  with `-std` aliases (`macos-metal*`) and one clang-ish form (`macosx_x86_64`); I could not
  disambiguate them. Avoid `-target` entirely and use `-mmacosx-version-min` + `-std`.
- **Whether `metallib` accepts `.air` files built for different targets**, and what it produces if it
  does. No Apple documentation and no reliable third-party report exists. My reading of the container
  format says there is no slice table to populate, so multi-slice linking is likely impossible rather
  than merely undocumented.
- **Whether a metallib with no matching GPU family fails at `newLibraryWithURL:` or at
  `newFunctionWithName:`.** Only anecdotal evidence, and the anecdotes point both ways.
- **The exact rejection message for an AIR whose triple names a newer OS than the running system.** No
  report found of a Metal-specific "built for newer macOS" error; I infer the mechanism from the
  triple and infer the failure from the surrounding C/C++ tooling behaviour.
- **Whether an Xcode 26 x86_64 slice actually launches and functions on Intel hardware.** Apple
  publishes the Universal `.xip`; nobody has tested it here, and my only supporting evidence is
  community reports plus the existence of the Apple-silicon-specific siblings.
- **Whether `xcodebuild -downloadComponent metalToolchain` succeeds at all on `macos-26-intel`**
  without extra permissions. The macos-26 runners are documented as needing it; whether the download
  works headless on a standard runner is untested.
- **Direct content of Apple Developer Forum threads** — the bot filter blocked every attempt, so the
  "standalone Metal Toolchain" and "MetalToolchain auto updates" threads are cited from search-index
  snippets only.
- **Apple's official position on running Xcode 26 on non-supported Intel Macs under OCLP.** The system
  requirements table lists only OS requirements, not a CPU allowlist, so nothing in Apple's docs
  forbids it — but Apple does not affirm it either.

## Sources

Primary:

- https://developer.apple.com/xcode/system-requirements/ (minimum macOS per Xcode, current as of 2026-10-02)
- https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components
  (Metal Toolchain download/import flow; universal-vs-Apple-silicon variants)
- https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf — **Version 4.1, 2026-06-04**;
  §1.6.10 `-std=` table, §1.6.15 `-arch` / `-gpu-family`, the "only Apple silicon supports new features
  in language standard 3.2 and above" note
- https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf — **May 21, 2026**; Apple-family GPUs only
- https://developer.apple.com/documentation/metal/mtlgpufamily and `.../common3` (availability `macOS: 10.15.0 - 27.0.0`)
- https://developer.apple.com/documentation/metal/mtllanguageversion/version3_1 and `.../version3_2`
- https://developer.apple.com/documentation/metal/mtllibraryerrordomain
- https://developer.apple.com/library/archive/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/Dev-Technique/Dev-Technique.html
- https://developer.apple.com/metal/tools/
- https://clang.llvm.org/docs/ClangCommandLineReference.html (`-target`, `-mtargetos`, `-mmacosx-version-min`)
- https://docs.github.com/en/actions/reference/runners/github-hosted-runners (standard runners, public + private tables)
- https://github.com/actions/runner-images/blob/main/images/macos/{macos-15,macos-15-arm64,macos-26,macos-26-arm64}-Readme.md
- https://xcodereleases.com/ (build numbers, Universal vs Apple-silicon downloads)

Third-party / issue trackers:

- https://github.com/actions/runner-images/issues/13014 (Metal Toolchain absent on Xcode 26 runners)
- https://github.com/actions/runner-images/issues/13080
- https://github.com/ggml-org/llama.cpp/issues/26370, https://github.com/ggml-org/llama.cpp/issues/11071
- https://github.com/ml-explore/mlx/issues/3337 (Metal Toolchain 32023 stdlib namespace change)
- https://github.com/tinygrad/tinygrad/issues/2226 (`MTLLibrary is not formatted as a MetalLib file`)
- https://github.com/ggml-org/llama.cpp/blob/master/ggml/src/ggml-metal/CMakeLists.txt (upstream metal invocation; `-mmacosx-version-min` / `-mtargetos` / `-std`, no `-target`)
- https://github.com/ggml-org/llama.cpp/blob/master/ggml/src/ggml-metal/ggml-metal-device.m (Common-family probing under `TARGET_CPU_X86_64`)
- https://github.com/XcodesOrg/xcodes (README — Xcode only, no components)
- https://github.com/darlinghq/darling/issues/326, https://discourse.nixos.org/t/using-metal-shader-compiler-inside-derivation/38773
  (Metal compilers closed source / Xcode-only)
- https://worthdoingbadly.com/metalbitcode/ (MTLB container + AIR = LLVM bitcode)
- https://medium.com/@samuliak/breaking-down-metals-intermediate-representation-format-41827022489c (AIR target triple)
- https://www.polpiella.dev/metal-toolchain-ci-cd (Xcode 26 Metal Toolchain CI recipe)
