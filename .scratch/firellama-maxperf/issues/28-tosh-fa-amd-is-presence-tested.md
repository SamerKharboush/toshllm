# 28: TOSH_FA_AMD is presence-tested, so =0 enables it

**What to build:** the flag's semantics written down and its consequence checked, because an on/off comparison built on this flag may not have had an off arm.

**Blocked by:** None (can start immediately).

**Status:** open 2026-10-17 — semantics verified from source; consequence not yet searched for.

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
