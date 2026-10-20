# 67: the plan offloads a 35B MoE that the CPU runs 76x faster

Status: ready-for-agent
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
