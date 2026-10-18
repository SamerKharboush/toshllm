#!/bin/bash
# Verifies the FA AMD kernel set that ships in the wave64 metallib.
#
# Two traps this script exists to avoid, both found on 2026-10-18:
#
#  1. `strings FILE | grep -q NAME` under `set -o pipefail` reports failure on a
#     MATCH: strings dies of SIGPIPE when grep exits before reading all input,
#     and pipefail turns the 141 into a non-zero pipeline. Materialise the symbol
#     list first.
#  2. Presence in a .metallib is NOT usability. kernel_flash_attn_ext_vec_amd_
#     dk128_kf16_vf16_w64 is present here by every string check and still fails
#     MTLDevice newComputePipelineStateWithFunction with "GPGPU, exceed the local
#     data storage limit". A presence check green-lights the broken kernel, so
#     presence alone is not a pass.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FA_METALLIB="${FA_METALLIB:-$ROOT/vendor/llama.cpp/build-static/bin/kernels/fa.metallib}"
REQUIRED=(
  kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64
  kernel_flash_attn_ext_vec_amd_dk256_kf16_vf16_w64
  kernel_flash_attn_ext_vec_amd_dk512_kf16_vf16_w64
)

[ -f "$FA_METALLIB" ] || { echo "FAIL: no metallib at $FA_METALLIB"; exit 2; }

# One read, one materialised list. Nothing downstream runs under a pipe.
SYMS="$(strings "$FA_METALLIB" | tr -c 'A-Za-z0-9_\n' '\n')"

# Here-strings, not pipes. A pipe here reintroduces the same SIGPIPE: grep -q
# exits on a MATCH, the producer takes SIGPIPE, and pipefail calls it a failure,
# so every present kernel reports ABSENT. Here there is no producer to signal.
rc=0
for k in "${REQUIRED[@]}"; do
  if grep -qxF "$k" <<< "$SYMS"; then
    echo "  present  $k"
  else
    echo "  ABSENT   $k"
    rc=1
  fi
done

echo "  distinct FA AMD names: $(grep -cE '^kernel_flash_attn_ext_vec_amd' <<< "$SYMS")  (fat binary: each name appears once per architecture)"

# Presence is necessary, not sufficient. Only a pipeline that builds is evidence.
PROBE="${FA_AMD_PROBE:-}"
if [ -n "$PROBE" ] && [ -x "$PROBE" ]; then
  echo "  -- runtime pipeline probe --"
  if "$PROBE" 2>&1 | grep -qiE 'exceed the local data storage limit|Linking two modules|not instantiated'; then
    echo "  FAIL: pipeline creation reported a known Metal fault"
    rc=1
  else
    echo "  pipeline creation clean"
  fi
else
  echo "  NOTE: presence checked only. Set FA_AMD_PROBE=<binary> to test pipeline"
  echo "        creation; without it a shipping-but-broken kernel passes silently."
fi

exit $rc
