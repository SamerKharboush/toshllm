# 08 — 27B acceptance run

Status: open
Type: task

## Question

Does Ternary-Bonsai-2-27B load and generate coherently on this machine, and at what tok/s under which split?

## Context

Model on disk: `~/models/Ternary-Bonsai-2-27B-PQ2_0.gguf`. This is the "biggest model" acceptance proof. Run it under the best-known config when the ticket is claimed (tensor+events if it fits memory, else layer + Dynamic MoE partial bank), record pp/tg, RAM/VRAM, plan coverage, plus a coherence sample. Long run — claim only when the machine is free. Result feeds ticket 06 if the planner undersizes, and graduates the 35B fog (or keeps it fog with numbers).

## Answer

(unresolved — record: config, pp/tg, memory, coherence sample)
