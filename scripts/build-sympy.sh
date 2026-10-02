#!/bin/zsh
# Builds the self-contained symbolic math runtime in vendor/tosh-sympy: a pinned CPython,
# SymPy, mpmath and the helper from helpers/tosh-sympy. Nothing here uses a Python from the
# system, and every download is checked against a pinned SHA-256.
#
#   ./scripts/build-sympy.sh              # host architecture
#   ARCH=x86_64 ./scripts/build-sympy.sh  # cross-build (CI on Apple Silicon runners)
set -e
cd "$(dirname "$0")/.."
ROOT="$PWD"
ARCH="${ARCH:-$(uname -m)}"

PYTHON_VERSION="3.13.16"
PYTHON_RELEASE="20261001"   # astral-sh/python-build-standalone
SYMPY_VERSION="1.14.0"
MPMATH_VERSION="1.3.0"

typeset -A PYTHON_SHA256=(
    x86_64 a88bef59d9dd61ba4210772cce57a4b4cb963aa745ab956f7cc79ba60f9e2523
    arm64  d00669acb53c1b014f1fcf5eaea740d8e45c3aff4b1e0244dc0f8697fb211a82
)
SYMPY_SHA256="e091cc3e99d2141a0ba2847328f5479b05d94a6635cb96148ccb3f34671bd8f5"
MPMATH_SHA256="a0b2b9fe80bbcd81a6647ff13108738cfb482d481d826cc0e02f5b35e5c88d2c"

OUT="$ROOT/vendor/tosh-sympy"
CACHE="$ROOT/vendor/.downloads"
STAMP="$PYTHON_VERSION+$PYTHON_RELEASE sympy-$SYMPY_VERSION mpmath-$MPMATH_VERSION $ARCH"
mkdir -p "$CACHE"

fetch() {
    local url="$1" sha="$2" file="$CACHE/${1:t}"
    if [ ! -f "$file" ] || [ "$(shasum -a 256 "$file" | cut -d' ' -f1)" != "$sha" ]; then
        curl -fL --retry 4 --retry-delay 5 -o "$file" "$url"
    fi
    if [ "$(shasum -a 256 "$file" | cut -d' ' -f1)" != "$sha" ]; then
        echo "ERROR: checksum mismatch for ${file:t}" >&2
        rm -f "$file"
        exit 1
    fi
    echo "$file"
}

python_tarball() {
    local triple="$1"
    [ "$triple" = "arm64" ] && triple="aarch64"
    fetch "https://github.com/astral-sh/python-build-standalone/releases/download/$PYTHON_RELEASE/cpython-$PYTHON_VERSION+$PYTHON_RELEASE-$triple-apple-darwin-install_only_stripped.tar.gz" \
          "${PYTHON_SHA256[$1]}"
}

case "$ARCH" in
    x86_64|arm64) BASE_ARCH="$ARCH" ;;
    universal)    BASE_ARCH="x86_64" ;;
    *) echo "ERROR: unsupported ARCH '$ARCH'" >&2; exit 1 ;;
esac

SYMPY_WHEEL="$(fetch "https://files.pythonhosted.org/packages/py3/s/sympy/sympy-$SYMPY_VERSION-py3-none-any.whl" "$SYMPY_SHA256")"
MPMATH_WHEEL="$(fetch "https://files.pythonhosted.org/packages/py3/m/mpmath/mpmath-$MPMATH_VERSION-py3-none-any.whl" "$MPMATH_SHA256")"
PYTHON_TARBALL="$(python_tarball "$BASE_ARCH")"

rm -rf "$OUT"
mkdir -p "$OUT"
tar xzf "$PYTHON_TARBALL" -C "$OUT"

PY="$OUT/python"
LIB="$PY/lib/python${PYTHON_VERSION%.*}"

if [ "$ARCH" = "universal" ]; then
    SLICE="$(mktemp -d)"
    tar xzf "$(python_tarball arm64)" -C "$SLICE" "python/bin/python${PYTHON_VERSION%.*}"
    lipo -create "$PY/bin/python${PYTHON_VERSION%.*}" "$SLICE/python/bin/python${PYTHON_VERSION%.*}" \
         -output "$PY/bin/python.universal"
    mv "$PY/bin/python.universal" "$PY/bin/python${PYTHON_VERSION%.*}"
    rm -rf "$SLICE"
fi

# The interpreter is one static executable. Everything below is not needed to run SymPy,
# and removing the two loadable modules leaves a single binary to sign.
find "$PY/bin" -mindepth 1 ! -name "python${PYTHON_VERSION%.*}" -delete
mv "$PY/bin/python${PYTHON_VERSION%.*}" "$PY/bin/python3"
rm -rf "$PY/include" "$PY/share" "$PY/lib/pkgconfig" "$PY/lib"/lib*.dylib \
       "$PY/lib"/(itcl|tcl|tk|thread)*(N) \
       "$LIB/lib-dynload"/* "$LIB/site-packages"/* "$LIB"/config-* \
       "$LIB"/(test|idlelib|tkinter|turtledemo|ensurepip|venv|pydoc_data|lib2to3|curses|dbm|sqlite3|wsgiref|xmlrpc|unittest|_pyrepl)(N) \
       "$LIB"/(turtle|pydoc|doctest|pdb|smtplib|ftplib|imaplib|poplib|mailbox|webbrowser|tarfile|zipapp).py(N)
find "$LIB" -name '__pycache__' -type d -prune -exec rm -rf {} +

unzip -q "$SYMPY_WHEEL" -d "$LIB/site-packages"
unzip -q "$MPMATH_WHEEL" -d "$LIB/site-packages"
find "$LIB/site-packages" -type d \( -name tests -o -name benchmarks \) -prune -exec rm -rf {} +
rm -rf "$LIB/site-packages"/*.dist-info "$LIB/site-packages"/isympy.py "$LIB/site-packages"/bin(N)

mkdir -p "$OUT/tosh_sympy"
cp "$ROOT"/helpers/tosh-sympy/tosh_sympy/*.py "$OUT/tosh_sympy/"
cp -R "$ROOT/helpers/tosh-sympy/licenses" "$OUT/licenses"

# The app bundle is read-only and signed, so the bytecode is built here and never checked
# against the sources at run time. compileall needs its own sources, so it runs before they go.
BUILD_PY="$PY/bin/python3"
if ! "$BUILD_PY" -I -c 'pass' 2>/dev/null; then
    # cross-build: the target interpreter cannot run here, so use the host one of the same release
    HOST="$(mktemp -d)"
    tar xzf "$(python_tarball "$(uname -m)")" -C "$HOST"
    BUILD_PY="$HOST/python/bin/python${PYTHON_VERSION%.*}"
fi
"$BUILD_PY" -I -m compileall -q -b -j 0 --invalidation-mode unchecked-hash "$LIB"
"$BUILD_PY" -I -m compileall -q -j 0 --invalidation-mode unchecked-hash "$OUT/tosh_sympy"
[ -n "$HOST" ] && rm -rf "$HOST"
# the libraries ship as bytecode only: half the size and half the files to seal in the signature
find "$LIB" -name '*.py' -delete

echo "$STAMP" > "$OUT/VERSION"
echo "symbolic math runtime ready at $OUT ($(du -sh "$OUT" | cut -f1), $STAMP)"
