#!/bin/bash
# Enforces clause (c) of specs/metal-fa-contract.md: on the wave64 FA AMD path, no build the
# probe refused is a dead end. Compares the names the selector can construct against the
# refusal record in the contract -- that record is existing probe output, not a new
# measurement, so this runs anywhere.
#
#   tools/check-fa-amd-contract.sh                  # both inputs from the tree
#   FA_CONTRACT=<path> FA_PATCHES=<dir>             # override the inputs
#   FA_REFUSED_EXTRA="name name2"                   # seed extra refusals (failure control)
#
# Exit 0 when every refused name the vec selector can construct is covered by a `_lds32`
# twin that is not itself refused, 1 on a dead end, 2 when an input is missing or unusable.
#
# What a green does NOT mean, and the contract says it in the same words: the selector still
# requests the refused plain name first and falls back to the twin (demoting it is ticket 39,
# blocked on the engine run). This check verifies the fallback exists and is not refused.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONTRACT="${FA_CONTRACT:-$ROOT/specs/metal-fa-contract.md}"
PATCHES="${FA_PATCHES:-$ROOT/patches/llama}"

echo "FA AMD contract check: clause (c), specs/metal-fa-contract.md"
echo "  contract: $CONTRACT"

[ -f "$CONTRACT" ] || { echo "FAIL: no contract at $CONTRACT" >&2; exit 2; }

# The refusal record. Empty means the check would pass vacuously, which is the one way a
# device-scoped guard can go silent, so an empty record is an error rather than a green.
refused="$(sed -n '/refused-names-begin/,/refused-names-end/p' "$CONTRACT" |
           grep -E '^kernel_flash_attn_ext_vec_amd')"
if [ -z "$refused" ]; then
    echo "FAIL: $CONTRACT records no refused names; a device-scoped check with an empty" >&2
    echo "      record would pass vacuously" >&2
    exit 2
fi
# Seeded refusals are the failure control: they must be able to turn this check red.
if [ -n "${FA_REFUSED_EXTRA:-}" ]; then
    refused="$refused
$(echo "$FA_REFUSED_EXTRA" | tr ' ' '\n' | grep -E '^kernel_flash_attn_ext_vec_amd')"
    echo "  seeded refusals: $FA_REFUSED_EXTRA"
fi

# What the selector can construct. Read from the tracked series rather than a vendor
# checkout: vendor/ is gitignored, can lag the series, and is absent on a fresh CI checkout.
[ -d "$PATCHES" ] || { echo "FAIL: no patch series at $PATCHES" >&2; exit 2; }
SRC="$(find "$PATCHES" -name '*.patch' -exec grep -h '^+' {} + )"
echo "  selector: $PATCHES (tracked series)"

grep -q 'kernel_flash_attn_ext_vec_amd_dk%d' <<< "$SRC" || {
    echo "FAIL: the series no longer constructs kernel_flash_attn_ext_vec_amd_dk%d...;" >&2
    echo "      re-derive this check against the new selector" >&2; exit 2; }
grep -q '"%s_lds32"' <<< "$SRC" || {
    echo "FAIL: the series no longer builds the twin as <requested name>_lds32;" >&2
    echo "      the coverage this check asserts no longer holds" >&2; exit 2; }

rc=0
covered=0
skipped=0
while read -r name; do
    [ -n "$name" ] || continue
    case "$name" in
        # The twin itself refused: the fallback lands on a name with nothing after it.
        kernel_flash_attn_ext_vec_amd_dk*_w64_lds32|kernel_flash_attn_ext_vec_amd_dk*_w64_wg32_lds32)
            echo "  DEAD END  $name  (requested as the twin, refused, nothing builds after it)"
            rc=1
            continue ;;
        # A name the vec selector requests on wave64, plain or split-cache.
        kernel_flash_attn_ext_vec_amd_dk*_w64|kernel_flash_attn_ext_vec_amd_dk*_w64_wg32)
            ;;
        *)
            echo "  out of scope  $name  (not a wave64 name the vec selector constructs)"
            skipped=$((skipped+1))
            continue ;;
    esac
    if grep -qxF "${name}_lds32" <<< "$refused"; then
        echo "  DEAD END  $name  (refused, and its twin ${name}_lds32 is refused too)"
        rc=1
    else
        echo "  covered   $name -> ${name}_lds32"
        covered=$((covered+1))
    fi
done <<< "$refused"

if [ "$rc" -ne 0 ]; then
    echo "FAIL: at least one refused build is a dead end on the wave64 selector path"
    exit 1
fi

echo "OK: $covered refused name(s) covered by a non-refused _lds32 twin, $skipped out of scope"
echo "    covered means absent from the refusal record; the twins that build are recorded in"
echo "    the contract's method section. The plain request is still made first (ticket 39)."
