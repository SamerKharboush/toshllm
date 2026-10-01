# 03 — mgpuPeer default on non-bridged cards

Status: open
Type: task

## Question

Should `mgpuPeer` default stay true for this hardware, and what is the measured cost either way?

## Context

`Server.swift:119-122`: `mgpuPeer` defaults true; comment says worth 16% of prefill and only safe alongside `mgpuEvents`. Measured on the D700 pair (peer group 0, not bridged): tensor peer 141.85 vs none 141.71 — inert. Peer copy across a PCIe bus with no fabric may cost on larger models or longer contexts; never measured above 4B/512pp. Decision needs a peer on/off run at 14B scale before changing the default or gating it on `peerGroups` (Hardware.swift already models groups — the app could default peer true only inside a real peer group).

## Answer

(unresolved — record: 14B peer on/off numbers, then default decision)
