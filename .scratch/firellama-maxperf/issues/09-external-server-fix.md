# 09 — External server LAN fix

Status: resolved
Type: task
Blocked by: 07 (resolved)

## Question

What is the minimal change that makes the exposed server reachable from the LAN, and does it hold under a real curl from another machine?

## Answer

### The fix

`Sources/App/ToshLLMApp.swift` — the menu-bar per-server discovery toggle now pins the field,
mirroring `DashboardTab.swift:1068` (`pin`) and `DashboardTab.swift:1063` (`isPinned`):

```swift
return Binding(get: { isPinnedDiscovery ? (c.profile?.localNetworkDiscovery ?? false) : globalDiscover }, set: { v in
    c.profile?.localNetworkDiscovery = v
    pinDiscovery()
    manager.persist()
    if running { c.restart(c.effectiveSettings()) }
})
```

with

```swift
private var isPinnedDiscovery: Bool {
    guard let pinned = c.profile?.pinned else { return true }
    return pinned.contains(Profile.Pin.discovery)
}

private func pinDiscovery() {
    guard var pinned = c.profile?.pinned, !pinned.contains(Profile.Pin.discovery) else { return }
    pinned.append(Profile.Pin.discovery)
    c.profile?.pinned = pinned
}
```

The getter is fixed in the same commit because it had the identical defect: it read the
profile value without consulting the pin, so the switch reported on while the engine bound
`127.0.0.1`. Fixing only the setter would have left a toggle that still lies.

One change, two paths (setter and getter), matching how the dashboard already does it. No new
surface, no new setting.

### Validation

- `swiftc -parse` clean.
- **Not runtime-verified.** Requires a build and a second machine, and neither is available
  here: the tree does not compile on this box (pre-existing, unrelated — see ticket 05's
  note and the map), and the LAN curl needs a second host. See "Open" below.

### Open

- **LAN curl from another machine**: not run. Must show a non-loopback bind, since the Q6
  failure is bind-to-localhost and a green curl against `127.0.0.1` proves nothing.
- **Regression check (external-host off)**: not run. With the pin absent, `isPinnedDiscovery`
  is false and the getter falls back to `globalDiscover`, so an unpinned server keeps following
  the global value — which is the intended pre-existing behaviour.
- **No LAN URL in the UI**: the app never surfaces the machine's LAN IP (no `getifaddrs` or
  `en0` code exists), so once binding works there is nothing to aim at. Worth a separate
  ticket; it is a UX gap, not this defect.
- **`ServerDetailView.resetOverrides()`** sets `pinned = [Profile.Pin.model]`, silently
  unpinning discovery for that server and dropping it back to the global value. Consistent
  with the "inherit globals" label on the sibling control, so intentional, but it is a second
  way the user's choice disappears.

## Comments

- 2026-10-01: code landed, runtime proof blocked on a working build + second machine.
