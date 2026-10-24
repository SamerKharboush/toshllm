# 66: the cells that keep the experts in the host produce garbage

Status: ready-for-agent
Type: bug
Spec: ../spec.md (Revision 8)

## Problem

Two flags that put the MoE expert weights in the host while the rest of the model sits on
the cards make the 35B fast and wrong.

| cell | decode tok/s | output |
|---|---|---|
| one-device (reference) | 0.1450 | correct |
| `-cmoe` | 9.8263 | coherent for ~250 characters, then one token repeated to the end |
| `--n-cpu-moe 16` | 5.9683 | same collapse, a different repeated token |
| `--n-cpu-moe 24` | 6.8473 | same |
| `--n-cpu-moe 32` | 10.3336 | same |

The reference is the same model on the CPU (`-ngl 0`): 11.0374 tok/s and a coherent 400
token answer with no junk in it. The GPU cells (`-ngl 99`, one card or two) produce the same
first 24 tokens as the CPU and stay coherent. Only the cells that move the experts to the
host and leave the rest on the card degenerate.

The evidence is in `../evidence/the-n-cpu-moe-cells-are-not-the-model-2026-10-20.md`.

## Why it matters

The speed of the broken cells is the fastest in the sweep, and the flags are the ones a
person reaches for when a model does not fit in VRAM. A user who passes `--n-cpu-moe 16`
gets a model that answers the first paragraph and then repeats a token, and the log has
nothing to say about it. The engine also has no check that the output is the model's.

## Change

Find where the mixed placement breaks the MoE path and fix it, or make the engine refuse
the combination. The gather, the dequantisation, the split of the expert matmul and the
device boundary are the places to look; the fork's own MoE path is `common/tosh-plan.cpp`
and the upstream expert dispatch in `src/llama-model.cpp` / `src/llama-graph.cpp`.

## Done when

- The 35B with `-cmoe` and with `--n-cpu-moe 16, 24, 32` generates the same text as the
  `-ngl 0` reference for 400 tokens, or the engine refuses the combination with a message
  that says why.
- The throughput of the fixed cells is measured, n >= 2, against the matrix in
  `../evidence/the-35b-placement-matrix-2026-10-20.md`.
- If it is fixed, the matrix is re-run and the broken rows are replaced, with the old rows
  left visible and the retraction noted.

## 2026-10-23: the planner no longer picks this path on a 64-lane card

Patch `moe/0047-the-plan-refuses-the-host-expert-fallback-on-a-64-lane-card.patch`. The change
was implemented by OpenCode (`opencode/glm-5.3-flash-free`) from a brief, then reviewed and
rebuilt here.
- When `TOSH_METAL_SIMD_WIDTH` is 64 and mixed execution does not fit, the plan no longer
  selects `PLAN_CLASSIC_NCMOE`. It refuses with limits `LEGACY_OFFLOAD_UNSAFE` and
  `NO_SAFE_FALLBACK`, and logs a remedy.
- `TOSH_AUTO=legacy` still forces the old path.

Gates passed:
- the build;
- 0 AVX2/FMA mnemonics, engine sha256 ebacf72b…;
- 52 of 52 patches apply cleanly at the pin.

**Owed:** a launch on a card where mixed execution does not fit but the fallback does
(card 0 at about 3.8 GiB free, as on 2026-10-22), showing the refusal and its log line. It
could not run on 2026-10-23: the user's Qwen3-14B server held both cards, 0.14 GB free each.

The bug itself is not fixed. Explicit `--n-cpu-moe` / `-cmoe` flags still reach this path.

## 2026-10-24: the owed refusal gate, shown

Method: `TOSH_AUTO_SIM_VRAM_MIB` simulates a smaller card on card 1. The 35B Q6_K, `-c 16384
--dynamic-moe on`.
- **Dry runs at 4500, 4700, 4900 and 5100:** the plan is `PLAN_UNSUPPORTED` with limits
  `LEGACY_OFFLOAD_UNSAFE, VRAM_LIMIT, NO_SAFE_FALLBACK`.
- **The same with `TOSH_AUTO=legacy`:** `PLAN_CLASSIC_NCMOE`. The override still forces the
  old path.
- **A real launch at 4700:** exit 1, and the model is not loaded. The log reads "mixed
  execution does not fit this card, and the --n-cpu-moe fallback answers garbage on a
  64-lane GPU; free VRAM (...), run on the host with -ngl 0, or force it with
  TOSH_AUTO=legacy".

Noted, not resolved: under the simulation, Dynamic MoE was refused even at 5100. The real
card planned it at about 5.0 GiB free on 2026-10-22/23. So the simulation's boundary is not
the real card's, and the simulation is good for showing the refusal, not for locating where
it starts.
