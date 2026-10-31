import glob, os, struct, sys

Q6 = {(1024,1024),(1024,1280),(1024,1536),(1024,1792),(1024,2048),
      (4096,1024),(4096,1280),(4096,1536),(4096,1792),(4096,2048),
      (8192,1024),(8192,1280),(8192,1536),(8192,1792),(8192,2048),
      (12288,1024),(12288,1280),(12288,1536),(12288,1792),(12288,2048)}
Q4 = {(2560,6144),(2560,8192),(2560,10240),(2560,12288),(2560,14336),
      (8192,6144),(8192,8192),(8192,10240),(8192,12288),(8192,14336),
      (14336,6144),(14336,8192),(14336,10240),(14336,12288),(14336,14336)}
NAMES = {0:'F32',1:'F16',2:'Q4_0',3:'Q4_1',6:'Q5_0',7:'Q5_1',8:'Q8_0',9:'Q8_1',
         10:'Q2_K',11:'Q3_K',12:'Q4_K',13:'Q5_K',14:'Q6_K',15:'Q8_K'}
SZ = {0:1,1:1,2:2,3:2,4:4,5:4,6:4,7:1,10:8,11:8,12:8}

class R:
    def __init__(s, f): s.f = f
    def raw(s, n): return s.f.read(n)
    def u32(s): return struct.unpack('<I', s.f.read(4))[0]
    def u64(s): return struct.unpack('<Q', s.f.read(8))[0]
    def i64(s): return struct.unpack('<q', s.f.read(8))[0]
    def s_(s):
        n = s.u64(); return s.f.read(n).decode('utf-8', 'replace')
    def val(s, t):
        if t == 8: return s.s_()
        if t == 9:
            et = s.u32(); n = s.u64()
            for _ in range(n): s.val(et)
            return None
        n = SZ[t]; s.f.read(n); return None

def scan(path):
    with open(path, 'rb') as f:
        r = R(f)
        if r.raw(4) != b'GGUF': raise ValueError('not gguf')
        ver = r.u32(); nt = r.u64(); nkv = r.u64()
        arch = '?'
        for _ in range(nkv):
            k = r.s_(); t = r.u32()
            if k == 'general.architecture' and t == 8:
                arch = r.s_(); continue
            r.val(t)
        out = []
        for _ in range(nt):
            name = r.s_(); nd = r.u32()
            dims = [r.u64() for _ in range(nd)]
            ty = r.u32(); r.u64()
            out.append((name, NAMES.get(ty, 'T%d' % ty), dims))
        return arch, out

files = sorted(glob.glob('/Users/sam/models/**/*.gguf', recursive=True))
hits, seen, skipped = {}, {}, []
for path in files:
    base = os.path.basename(path)
    try:
        arch, ts = scan(path)
    except Exception as e:
        skipped.append((base, repr(e)[:60])); continue
    print('##', base, arch, 'tensors=%d' % len(ts), flush=True)
    for name, ty, dims in ts:
        if ty not in ('Q6_K', 'Q4_K') or len(dims) < 2:
            continue
        k, rows = dims[0], dims[1]
        grid = Q6 if ty == 'Q6_K' else Q4
        if (k, rows) in grid:
            hits.setdefault((ty, k, rows), set()).add((base, name, arch))
        seen.setdefault((ty, k, rows), set()).add(base)

print('\n=== tested (k, rows) that occur in /Users/sam/models ===')
for key in sorted(hits):
    print('HIT', key, 'files=%d' % len({h[0] for h in hits[key]}), sorted(hits[key])[:3])
print('\n=== every Q4_K/Q6_K (k, rows) in the models, with test-grid membership ===')
for key in sorted(seen):
    t, k, rows = key
    grid = Q6 if t == 'Q6_K' else Q4
    print('   ', key, 'IN-GRID' if (k, rows) in grid else '-', 'files=%d' % len(seen[key]))
print('\nskipped:', skipped)
