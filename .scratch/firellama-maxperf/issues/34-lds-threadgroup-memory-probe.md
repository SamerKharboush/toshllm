# 34: measure the dk128 threadgroup memory request

Status: resolved
Blocked by: none
Spec: ../spec.md

## Problem

The dk128 flash-attention pipeline fails creation and the only public account of the
fault attributes it to a threadgroup memory request over the 32 KB ceiling. We have
never measured ours.

## Change

A probe that reads the pipelines requested threadgroup memory in bytes on device
index 2 and prints it beside the ceiling, recording the drivers exact fault string
so the driver wording and our number are not conflated.

## Evidence

A byte count from this hardware. The driver string quoted verbatim. No layout change
is proposed by this ticket; that is a separate decision taken only if the measurement
exceeds the ceiling.
