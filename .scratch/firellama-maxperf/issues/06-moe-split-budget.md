# 06 — MoE split-budget sizing

Status: open
Type: task

## Question

Does `AutoMemoryPlan` size the Dynamic MoE expert bank against the split budget (~12GB) or a single card, and what changes so 27B-class models use both?

## Context

`Hardware.swift` already models `splitEligibleGPUs`, `combinedVramGB`, `peerGroups` — but `AutoMemoryPlan.swift` (299 lines) has no direct split refs (per earlier mapping). The 27B acceptance run (Ternary-Bonsai-2-27B-PQ2_0, on disk) via Dynamic MoE partial bank is the proof. Decision needs: read the planner's budget math, run the 27B load, record RAM/VRAM/plan coverage, then adjust sizing to split budget with per-device and per-buffer ceilings respected.

## Answer

(unresolved — record: planner math findings, 27B load numbers, sizing change)
