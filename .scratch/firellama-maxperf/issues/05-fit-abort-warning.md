# 05 — Fit-abort warning

Status: resolved
Type: task

## Question

What should the planner do when `--fit` is requested but `-ngl 99` (or any preset) makes it abort silently?

## Answer

The abort was never silent in the engine — it was silent in the app.

`vendor/llama.cpp/common/fit.cpp:464` throws `common_params_fit_exception` when
`n_gpu_layers` was already set by the user. `common_fit_params` catches it at `fit.cpp:894-896`
and logs at `LOG_WRN`:

```
not fitting params to free device memory: n_gpu_layers already set by user to 99, abort; continuing with the parameters as given
```

So the run continues unfitted by design, with one warning line in a log the user never opens.
That is why the measured §1/§2 runs looked identical: fitting never engaged in either.

The smallest change that makes the silent path loud is app-side: surface the warning the engine
already emits.

### The fix

- `Sources/Servers/Server.swift`: new `@Published var fitNote: String?`, reset on each launch,
  set from `consume()` when a line contains `not fitting params to free device memory`. The
  engine's own reason text is kept after the colon so the user sees *why* it gave up, not just
  that it did.
- `Sources/Servers/ServerOverviewView.swift`: orange `exclamationmark.triangle.fill` label on the
  server card, alongside the existing plan note, with a tooltip spelling out that the engine
  continued with the parameters as given.

Reusing the existing plan-note surface was deliberate: one place already shows engine memory
warnings, so a second mechanism would be a second place for users to learn.

Not changed: the fit policy itself. Making fitting run before the `-ngl` preset applies is a
behaviour change to the engine, and the ticket's own rule was the smallest change that makes
the silent path loud.

### Validation

`swiftc -parse` clean on both files. **Not runtime-verified** — the tree does not compile on
this box (see the map's Blocked section), so there is no app to drive.

## Comments

- 2026-10-01: resolved. Engine already warned; app now surfaces it. Runtime proof owed a build.
