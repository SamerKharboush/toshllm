# 03 — mgpuPeer default on non-bridged cards

Status: resolved
Type: task

## Question

Should `mgpuPeer` default stay true for this hardware, and what is the measured cost either way?

## Answer

**No. Gated on topology.** Measured at 14B on the tensor split, 12 threads,
`GGML_METAL_DEVICE_LIST=0,1`, peer group 0 (not bridged):

| config | pp512 | tg64 |
| --- | --- | --- |
| no flags | 41.40 | 8.55 |
| `TOSH_MGPU_PEER=1` + `TOSH_MGPU_EVENTS=1` | 43.07 | 8.55 |
| `TOSH_MGPU_EVENTS=1` only | 43.08 | 8.54 |

The +4% on prefill is `TOSH_MGPU_EVENTS`. **With events held on, peer alone moved pp by 0.00
and tg by 0.00.** The earlier 4B numbers (141.71 vs 141.85) were consistent with that; at 14B
the two flags separate cleanly.

So the flag the code described as "worth 16% of the prefill" buys nothing measurable on a pair
with no fabric link — and that comment describes a bridged pair, which this is not.

### The change

`Sources/Servers/Server.swift`:

```swift
if mgpuPeer && isSplitting && effectiveSplitMode == "tensor" && Self.peerBridgeAvailable {
    env["TOSH_MGPU_PEER"] = "1"
}
```

with

```swift
/// A group of two or more is the only evidence of a link: a card with no bridge reports
/// group 0, and `peerGroups` drops those.
static var peerBridgeAvailable: Bool {
    HardwareInfo.detect().peerGroups.contains { $0.count >= 2 }
}
```

The user toggle is untouched, so a bridged pair (W6800X, Vega II Duo) keeps the flag, and the
env can still be forced by hand to test the hypothesis on a pair that reports no link.

Gating on topology rather than flipping the default is the better shape: the default was right
for the hardware the flag was written for and wrong here, and one condition serves both.

Full numbers in `docs/mgpu-peer-2026-10-02.md`.

### Validation

`swiftc -parse` clean. **Not runtime-verified** — the app does not compile on this machine
(see the map's Blocked section).

## Comments

- 2026-10-01: earlier 4B run showed peer inert (141.71 vs 141.85) but could not separate it
  from events.
- 2026-10-02: resolved at 14B. Peer isolated against events: no effect. Gated on peerGroups.
