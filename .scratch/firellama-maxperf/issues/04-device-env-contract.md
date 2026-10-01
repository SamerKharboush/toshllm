# 04 — Device-env contract (DEVICE_LIST vs DEVICES)

Status: open
Type: task

## Question

How should the app guarantee GPU1 actually opens on the layer path, given `GGML_METAL_DEVICE_LIST=0,1` alone leaves MTL1 closed there while `GGML_METAL_DEVICES=2` opens it?

## Context

Measured: layer split with DEVICE_LIST only = single-device numbers (78.6 vs 78.7); with DEVICES=2 both GPUs init. App seam (`Server.swift:644-658`) already sets DEVICE_LIST iff gpuList>=2, DEVICES iff multiGPU-without-list, INDEX iff single. So the app may already be correct and only the bench harness was misleading — verify by reading what env the app actually exports for a 2-GPU layer config (startupBanner, Server.swift:1822-1842) and running one app-launched bench. If the app path is correct, the fix is docs + a harness tweak; if not, fix the seam. Either way the silent-single-GPU outcome must become loud (log which devices opened).

## Answer

(unresolved — record: app-exported env for layer-2GPU, verdict app-correct vs seam-fix)
