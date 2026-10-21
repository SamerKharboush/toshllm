/*
 * The AVX2 positive control.
 *
 * Built by ab.sh on every run, never committed as a binary. If this file stops
 * producing a binary that trips the disassembly scan and SIGILLs on a pre-AVX2
 * host, the harness fails rather than quietly passing.
 *
 * Expected, on this machine (Xeon E5-2697 v2, AVX but no AVX2):
 *   otool -tvV -> contains vpermps
 *   widened scan -> >= 1 hit
 *   execution -> exit 132 (SIGILL)
 *
 * The `used` and `noinline` attributes are load-bearing: without them the
 * optimiser deletes the function and the control silently becomes a plain
 * binary that scores zero, which is how a check rots into a passing fixture.
 */
#include <immintrin.h>

__attribute__((target("avx2"), used, noinline))
static __m256i avx2_probe(__m256i a, __m256i b) {
    return _mm256_permutevar8x32_epi32(a, b);
}

__attribute__((target("avx2"), used, noinline))
static __m256i avx2_broadcast(__m256i a) {
    return _mm256_permute4x64_epi64(a, 0x1b);
}

__attribute__((target("avx2")))
int main(void) {
    __m256i a = _mm256_set1_epi32(1);
    __m256i b = _mm256_setzero_si256();
    __m256i r = avx2_probe(a, b);
    __m256i s = avx2_broadcast(r);
    return _mm256_extract_epi32(s, 0) & 1;
}
