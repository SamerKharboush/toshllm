# 12 — Ship hardening: LAN proof, memset test, CI probe, Metal toolchain

Status: mostly resolved
Type: bug + test

## Question

A grilling pass over the release gaps. Which ones are closable here, and what
is actually left?

## Answer

### LAN exposure — proven (Q5)

The fix was verified by reading code; now it is verified by running it. The
app was launched with LAN discovery on and a model selected, and the engine
it started bound to all interfaces:

```
args: ... --host 0.0.0.0 --port 18095 ... --split-mode layer
srv   llama_server: listening on http://0.0.0.0:18095
lsof: llama-ser 51354 sam 4u IPv4 *:18095 (LISTEN)
```

Reached over the machine's own LAN address (10.132.246.6), not loopback:

```
GET  http://10.132.246.6:18095/health      -> {"status":"ok"}
GET  http://10.132.246.6:18095/v1/models   -> 200
POST http://10.132.246.6:18095/v1/chat/completions
     -> coherent answer, finish_reason stop, 4.99 tok/s
```

**Not a two-machine proof.** This is one host reaching itself over a
non-loopback interface, so it proves the bind and the reachable-interface
path — which is where the bug was — but not another machine's firewall or
routing. A genuine second-host test is still owed.

### NSMakeRange fix — now covered by a test (Q6)

The overfill had no A/B because nothing in a text forward pass calls
`ggml_backend_tensor_memset` at a non-zero offset. Patch 0127 adds a test
that does exactly that: fill a known pattern across a tensor, memset one
sub-range at a non-zero offset, then verify the bytes before the range, the
bytes inside it, and the bytes after it.

Five cases, chosen so a length bug cannot pass:

| case | why |
|---|---|
| offset 0, size 256 | the length bug is invisible here; a control |
| offset 1024, size 256 | the canonical case |
| offset 3584, size 256 | an overfill runs to the end of the tensor |
| offset 4000, size 16 | 16 bytes to fill, 80 to clobber |
| offset 2048, size 2048 | fills the tail exactly |

Run against the **pre-fix** form, it fails exactly as predicted:

```
offset=1024  FAIL bytes after the range untouched (1024 clobbered)
offset=3584  FAIL bytes after the range untouched (256 clobbered)
offset=4000  FAIL bytes after the range untouched (80 clobbered)
offset=2048  FAIL bytes after the range untouched (2048 clobbered)
FAILED: 3 check(s)
```

Note the clobber counts equal the offset in the first two cases — that is
the signature of `length = offs + size`. Against the fixed form, all five
cases pass.

Registered as `llama_build_and_test`, gated on `GGML_METAL`, and run with
`MTL0` so it exercises the Metal path that had the bug.

### CI on push — broken on the fork, confirmed by probe (Q7)

Not inference this time. A push to `main` touching `Package.swift`, which is
in the workflow's own `paths` filter, created **zero** runs. A manual
dispatch does create one. So push events are not reaching Actions at all on
this fork — a fork-level setting, not a workflow defect. The probe commit
was reverted.

Until it is fixed, no commit on this fork gets a CI gate. Local runs are the
answer in the meantime.

### Metal toolchain — not installable here (Q2)

`xcodebuild -downloadComponent MetalToolchain` needs an Xcode app to
download into, and there is none:

```
xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer
directory '/Library/Developer/CommandLineTools' is a command line tools instance
```

`softwareupdate -l` offers only Safari and two macOS versions. So the
143 s first-launch shader compile stays, and the DMG still ships without
`kernels/`. This needs a machine with Xcode installed to build from, not a
flag that can be flipped here.

### 27B tensor split — closed as an architectural limit (Q4)

`ne[0]=6144` does not divide `ne[0]=9216` on the `qwen35` SSM state reshape.
Marking the tensor unsplittable would leave the scheduler with no answer for
a node that needs split data, and proving it degrades correctly needs a
numerical A/B against a single-GPU tensor run — the 27B needs both cards just
to load. The abort names the op and the dimensions; the layer split, which is
that model's only option, works.

### Notarization — out of reach (Q3)

Needs an Apple Developer identity and credentials in the fork's secrets.
The DMG stays ad-hoc and the README says to right-click Open.

## Verified

- full 122-patch series applies in order to a pristine checkout of 957538960
- patch 0127 reverse-applies against the vendor tree
- test-metal-memset: all five cases pass on the fixed engine, four of five
  fail on the pre-fix form
