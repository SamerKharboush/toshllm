# 28: TOSH_FA_AMD is presence-tested, so =0 enables it

**What to build:** the flag's semantics written down and its consequence checked, because an on/off comparison built on this flag may not have had an off arm.

**Blocked by:** None (can start immediately).

**Status:** REOPENED 2026-10-17 — right severity, wrong disposition.

## The finding

`TOSH_ENV` is a bare `getenv` wrapper (ggml-metal-impl.h:1515), verbatim:

```
#define TOSH_ENV(name) ([]() -> const char * { static const char * tosh_env_v = getenv(name); return tosh_env_v; }())
```

It does **not** normalise `"0"` to NULL. The AMD gate tests presence, not value:

```
if (TOSH_ENV("TOSH_FA_AMD") != NULL && !has_simdgroup_mm && fa_amd_width_ok && (...))
```

Therefore **`TOSH_FA_AMD=0` enables the AMD flash-attention path**, exactly as `=1` does. Only unsetting the variable turns it off.

Its siblings in the same tree are value-tested: `TOSH_CB_PROFILE` uses `strcmp(e, "0") != 0`, and `TOSH_MGPU_EVENTS` uses `v[0] == '1'`. `TOSH_FA_AMD` is the odd one out.

## Why it matters

The natural experiment for this kernel family is on-versus-off. Any run that used `TOSH_FA_AMD=0` as the off arm had the AMD path enabled in **both** arms, and its null result would have been reported as evidence about switching something off that was never switched off. That is the `TOSH_MGPU_NOWAIT` failure mode again, in a different flag.

## Acceptance criteria

- [ ] Every recorded invocation that used `TOSH_FA_AMD` is checked for whether it set the variable or unset it, and the list is recorded
- [ ] Any comparison whose off arm set the variable to 0 is identified, and its result marked as measuring the AMD path in both arms
- [ ] The flag's actual semantics are written next to the flag wherever it is documented
- [ ] Whether the gate should be corrected to a value test is decided, and if yes, that is a separate change with its own evidence

## Result: the trap is latent, the app is correct

**The app sets the variable only when the toggle is on.** `Sources/Servers/Server.swift:728`:

```swift
if effectiveFaAmd { env["TOSH_FA_AMD"] = "1" }
```

When the toggle is off it leaves the variable unset, which is the only thing that actually disables the AMD path. So the app's off arm is a real off arm, and the finding above has caused no measurement error in anything recorded here.

**No recorded use of `TOSH_FA_AMD=0` exists** anywhere in the repo or in the scratch data.

The other callers are unconditional and therefore also safe: the video, image and speech paths each set it to `"1"` when they need the kernel.

## What remains, and why it is still worth writing down

The flag stays a trap for the next person: it is presence-tested where its siblings are value-tested, so `TOSH_FA_AMD=0` means on. A future on/off comparison is one keystroke from a null result about nothing, which is the `TOSH_MGPU_NOWAIT` shape. The semantics are now recorded next to the flag's other documentation, which is the whole of what this ticket can achieve without changing behaviour.

Whether the gate *should* be value-tested is a code change, deliberately not made here: the flag works as the app uses it, and correcting it changes runtime behaviour for any user who has set it to 0 in Extra arguments.

## Note

`Sources/Servers/EngineCheck.swift:164` already carries a comment acknowledging the dependency ("without TOSH_FA_AMD the attention kernels are..."), so the app's authors saw this; what was missing was the value-versus-presence distinction.

## Reopened: the disposition was wrong

"Latent trap, no actual error" understates it because it treats the app as the only caller. The app is one caller. A knob whose **zero value turns the feature on** is a defect on its own terms: it will be set to 0 in a shell profile, a launchd environment, a plist, or a reproduction script by someone who means "off", and it will silently enable the AMD kernel.

Presence-tested at four sites, to be re-verified individually before this closes:
`ggml-metal-device.m:2185`, `ggml-metal-ops.cpp:3963`, `ggml-metal-ops.cpp:4271`, `src/llama-graph.cpp:2755`.

Either value-test it, or state the presence semantics in a comment at the wrapper so the next reader cannot mistake it. Ten minutes.

**Note on making the change:** the fix belongs in the patch series under `patches/`, not in the working tree. Editing the tree in place would break the provenance proved in ticket 14 — the tree would no longer equal pin plus series. Apply to the series, then re-replay.

- [ ] Each of the four sites re-verified by reading it, not from this list
- [ ] Decision taken: value-test, or document at the wrapper
- [ ] If value-tested, the change is made in the series and the replay re-run
- [ ] The exposure list is written down: every shell profile, plist, and reproduction script on this machine that writes TOSH_FA_AMD
