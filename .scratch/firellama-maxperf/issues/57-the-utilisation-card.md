# 57: the utilisation card

Status: done
Type: task
Spec: ../spec.md (Revision 8)

## Problem

tok/s cannot say which cores ran, how busy each GPU was, how much VRAM each device held, or
how much of the 64 GB was resident. The question the hardware actually gets used needs four
numbers per run, in both phases.

## Change

One command, four numbers, both phases. No root: `powermetrics` needs sudo and sudo is not
available unattended here, so the card reads the AMD drivers' IORegistry counters instead.

## Answer

`tools/utilcard.sh` landed. It reports per-device `GPU Activity(%)`, `Device Utilization %`,
`inUseVidMemoryBytes`, `vramFreeBytes`, `Core Clock(MHz)`, `Memory Clock(MHz)`,
`Temperature(C)`, `Total Power(W)`, plus process CPU %, thread count, RSS, host page state and
`hw.physicalcpu`. Shown non-zero on a live run before it was trusted.

First reading, 8B-Q4 at `-ngl 99 -sm layer`: one device holds 6,135,795,712 B with 241 MB free
at 850/1370 MHz and 128% activity; the other holds 80,633,856 B at 300/150 MHz and 0% activity.
The second D700 is idle -- expected for a model that fits on one card, and the reason rung 2
now has an instrument: a real split must show both devices busy at once.

The card also established the host: Xeon E5-2697 v2, 12 physical cores, 24 logical, 64 GB.
