# 35: run the threadgroup memory probe on the D700

Status: resolved
Blocked by: 34
Spec: ../spec.md

## Problem

Ticket 34 builds the instrument; this ticket produces the number.

## Change

Run the probe on the D700 and record the measurement, the driver fault string, and
whether the request exceeds the ceiling.

## Evidence

A recorded byte count and a yes/no on whether it exceeds 32768, with the raw probe
output kept.
