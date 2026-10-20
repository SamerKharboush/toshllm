# The second D700 was never registered, not starved of budget

## The probe, compiled against the OS, outside the engine

`/tmp/probe.swift`, `swiftc -O`, run while nothing else touched the GPU:

```
device_count=2
  [0] name=AMD Radeon HD - FirePro D700 registryID=1957 isLowPower=no isHeadless=no  recMaxWorkingSet=6144.0 MiB
  [1] name=AMD Radeon HD - FirePro D700 registryID=1954 isLowPower=no isHeadless=YES recMaxWorkingSet=6144.0 MiB
```

So H2 is refuted and H1 is refuted, and the third hypothesis is the right one:

- The OS exposes **two** D700s. Not one.
- Both advertise the **same** 6144 MiB working set. There is no small-budget card to
  round to nothing.
- The second card is **headless** (`isHeadless=YES`), which is why nothing draws to it, but
  it is not low power and it is not invisible.

**H1 (budget arithmetic) is impossible here.** A headless card advertising 6 GB does not
produce a zero-share tensor split.

## Why the engine only ever used one

`ggml/src/ggml-metal/ggml-metal.cpp:29`:

```c
static int g_devices = 1;
```

The Metal backend registers **one** device unless the environment says otherwise:

| variable | effect |
|---|---|
| `GGML_METAL_DEVICES=K` | register K devices, slot i -> the i-th discrete GPU |
| `GGML_METAL_DEVICE_LIST=a,b` | register the listed GPUs, slot i -> physical list[i] |
| `GGML_METAL_DEVICE_INDEX=N` | pin the single device to physical GPU N |

`ggml_metal_device_init` (line 1707) reads all three and maps each logical slot to a
physical `MTLCopyAllDevices()` entry. With none of them set, `ggml_metal_device_default_discrete()`
picks one card and the second D700 is never enrolled in the backend at all.

**So the second card was not idle because it got no budget. It was not in the backend.** Every
placement cell in the previous round, and every "rung 2 is not reached" line, was measuring a
one-device engine and calling it a split result.

## The experiment that settles it

Two devices registered, equal tensor split, 8B-Q4_K_M, `-ngl 99 -sm layer -ts 1,1`:

```
GGML_METAL_DEVICES=2 GGML_METAL_DEVICE_LIST=0,1 llama-server ... -ts 1,1 -sm layer
```

```
  gpu  inUseVidMemoryBytes=2986704896   vramFreeBytes=3127566272
  gpu  inUseVidMemoryBytes=2970939392   vramFreeBytes=3443695555
```

**Both cards hold VRAM.** Before this, one card held 2.99 GB and the other held the desktop's
80 MB. The model is now split across two D700s. The card that was "cold" was cold because
nothing had told the backend it existed.

Note the *same* split mode, the same `-ts 1,1`, the same model. The only change is the number
of devices the backend was told about.

## What the app already does

`Sources/Servers/Server.swift:729-743` sets `GGML_METAL_DEVICE_LIST` when the user picks two
GPUs and `GGML_METAL_DEVICES` for the "split across N GPUs" mode. So the product already has
the switch; the measurements were made without going through it.

## The headless card is not a second-class card

Pinning the engine to the headless one (`GGML_METAL_DEVICE_INDEX=1`), 8B-Q4_K_M:

```
  gpu  inUseVidMemoryBytes=5574066176  vramFreeBytes=540204992  Core 850MHz  Activity 98%  Temp 69C
  gpu  inUseVidMemoryBytes=244461568   vramFreeBytes=6170283968 Core 450MHz  Activity  0%  Temp 65C
```

and **8.40 tok/s**, against 8.28 tok/s on the display card. The headless D700 runs the model at
full clocks and full activity. It is the better card for compute: the display card also carries
the WindowServer.

## Method

- Probe: Swift, `MTLCopyAllDevices()`, compiled with `swiftc -O`, run outside the engine so it
  cannot contradict itself.
- Engine: this branch, `fce9e70e`, AVX1+F16C.
- Model: Qwen3-8B-Q4_K_M.
- `-ngl 99 -c 4096 -t 8`.
- The 2-device cell ran with `GGML_METAL_DEVICES=2 GGML_METAL_DEVICE_LIST=0,1` and
  `--tensor-split 1,1`.
- VRAM figures are the AMD IORegistry counters, read with `tools/utilcard.sh`.
