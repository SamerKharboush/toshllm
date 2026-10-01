# 07 — External server host: where is it dropped

Status: resolved
Type: research

## Question

Where in the app does the external-host setting get lost on the way to `--host`?

## Answer

**`Sources/App/ToshLLMApp.swift:291` — the menu-bar per-server discovery toggle wrote the profile value without pinning it.**

```swift
return Binding(get: { c.profile?.localNetworkDiscovery ?? false }, set: { v in
    c.profile?.localNetworkDiscovery = v
    manager.persist()
    ...
})
```

Every other write path pins `Profile.Pin.discovery` (`DashboardTab.swift:897`,
`ServerDetailView.swift:747`). This one did not.

### Why that loses the value

An added server always has a non-nil `pinned`: `Server.swift:1450` sets
`pinned = [Profile.Pin.model]` at creation, and `ServerManager.init` restores it verbatim.
`effectiveSettings()` (`Server.swift:1532-1541`) then takes the `applyPinned` branch, which
gates the field on the pin (`Profiles.swift:301`):

```swift
if pinned.contains(Profile.Pin.discovery), let v = p.localNetworkDiscovery { localNetworkDiscovery = v }
```

The gate fails, so the field stays at whatever `fromDefaults()` read — `false` —
and `Server.swift:293` emits `"--host", "127.0.0.1"`. The value was written and persisted,
just never read.

Decisive contrast: when `pinned` is nil, `apply` sets the field unconditionally
(`Profiles.swift:273`) and the value survives. The loss is specific to the
set-but-lacking-`.discovery` state, which is what every added server is in.

The getter had the same gap (`c.profile?.localNetworkDiscovery ?? false`, no pin check), so
the menu-bar switch read on while the engine bound localhost. That is the "the setting is
ignored" symptom exactly.

### Ruled out

- **Launch bypass**: every engine launch builds args from `settings.arguments`, which always
  carries `--host`. The only mutation is dropping `--mmproj` on retry.
- **Override/clamp**: no writer mutates the field after the toggle. The `apiKeyEnabled`
  interaction only adds a warning label, never a write or `.disabled`.
- **Second listener**: no `NWListener` anywhere; `NetService` is advertise-only. `currentPort`
  and `--port` come from the same struct.
- **Bundled engine**: `common/arg.cpp` parses `--host` normally; no patch touches host binding.
  `extraArgs` is appended last and would win, but only if the user typed `--host` there.

For the **primary** server the chain was already correct end to end, so if the defect is seen
there the remaining candidates are environmental (macOS firewall, or a per-model `extraArgs`
`--host`), not this bug.

## Comments

- 2026-10-01: resolved. Drop point found, fix applied to ticket 09.
