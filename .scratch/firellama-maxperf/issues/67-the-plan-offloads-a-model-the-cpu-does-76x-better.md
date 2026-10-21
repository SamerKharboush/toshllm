# 67: the plan offloads a 35B MoE that the CPU runs 76x faster

Status: resolved
Type: task
Spec: ../spec.md (Revision 8)

## Problem

The 35B Q6_K is a 256-expert MoE that uses 8 experts per token. On this machine the same
model, the same prompt and the same eight threads give:

| placement | decode | prompt eval |
|---|---|---|
| one D700, `-ngl 99 -sm tensor` | 0.1450 tok/s | 6.4086 tok/s |
| both D700s, `-ts 1,1` | 0.4387 tok/s | 10.9739 tok/s |
| host only, `-ngl 0` | 11.1015 tok/s | 23.4130 tok/s |

The card is 41% busy and the host 17.9% busy in the slow path, so neither is saturated,
and the page-in row says the host has the weights in the page cache (386 pages in the
decode window, against 35,813 for the GPU cell).

The app's plan puts the model on the card, because the card is where a model that fits is
supposed to go. For this model that is 76x away from the best placement that was measured.
The dense 8B is not: it decodes at 8.32 tok/s on the card, and the fork's own work made
the card path faster than the generic one.

## Change

Find the rule that decides the placement for a MoE model and add the measured case: a
model whose active expert set is small relative to its total is cheaper in RAM than on
the card, because the card path does not skip the inactive experts the way the host path
does.

The plan lives in the app (`Sources/Servers/Server.swift` and the plan it asks the engine
for) and in `common/tosh-plan.cpp` in the vendor tree.

## Done when

- The rule is stated in terms that a reader can check, with the measurement that produced
  it quoted.
- A 35B and an 8B are placed by the plan as the rule says, and both are measured after the
  change: the 35B on the host, the 8B on the card.
- The README says which placement a 35B gets on this machine, with the row that says so.

## Answer

**The app places a model that does not fit in the VRAM the run may use on the host, and
both models were measured after the change.** The evidence is in
`../evidence/the-app-places-a-model-that-does-not-fit-on-the-host-2026-10-21.md`.

The rule, in terms a reader can check: **a model whose weights do not fit in the VRAM the
run may use runs on the host.** The VRAM the run may use is the combined VRAM of the cards
the run splits across and one card's VRAM otherwise, less a 1 GB reserve per card, and the
host has to have room for the weights, the KV cache and the compute buffers. The
measurement that produced it: the same 35B Q6_K decodes at 0.1450 tok/s on one D700 and
11.1015 tok/s with everything on the host (R1, R2, R11), and a 27B Q8_0 at 0.0883 against
1.5972 (R19, R20). The card keeps a fraction of the weights and pays for the whole model
on every token; the host pays for the active part.

The launch the app builds now, read out of `ServerSettings.arguments` and
`ServerSettings.environment` for the files on this machine:

| model | weights | placement | the launch |
|---|---|---|---|
| 35B Q6_K | 26.56 GiB | host | `-ngl 0`, no `--n-cpu-moe`, no `--split-mode`, no card in the environment |
| 27B Q8_0 | 27.74 GiB | host | the same |
| 14B Q4_K_M | 8.38 GiB | card | `-ngl 99 --split-mode layer`, `GGML_METAL_DEVICES=2` |
| 8B Q4_K_M | 4.68 GiB | card | the same |

Measured after the change, with the launch the app builds and nothing else changed:

| cell | prompt eval | decode | answer |
|---|---|---|---|
| 35B Q6_K on the host | 23.1305 tok/s (sd 2.1807) | 10.1353 tok/s (sd 0.8144) | coherent |
| 8B Q4_K_M on the cards | 39.6722 tok/s (sd 3.2904) | 9.0028 tok/s (sd 0.0280) | coherent |

The README says which placement a 35B gets, in "Where the app puts a model", with R24 and
R25 next to it.

**What the rule does not do.** It does not override the user: an explicit "Full GPU" mode
in the Dynamic MoE settings keeps the model on the card, and the router mode keeps its own
per-model plan. The rule is keyed on the cards this fork measured, so a card it has not
measured keeps the path it had. And the weights are what the rule looks at: a model whose
weights fit but whose KV cache does not stays on the card, because the card is still the
faster place for the weights.
