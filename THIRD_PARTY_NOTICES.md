# Third-party notices

ToshLLM is GPL-3.0 (see [LICENSE](LICENSE)). The components below are redistributed inside
the app under their own licenses.

## Symbolic math runtime (`Contents/Resources/tosh-sympy`)

Built by `scripts/build-sympy.sh` from pinned releases, each checked against its SHA-256. The
full license texts are in [`helpers/tosh-sympy/licenses`](helpers/tosh-sympy/licenses) and are
copied into the app at `Contents/Resources/tosh-sympy/licenses`.

| Component | Version | License | Text |
|---|---|---|---|
| SymPy | 1.14.0 | BSD-3-Clause | `LICENSE.sympy.txt` |
| mpmath | 1.3.0 | BSD-3-Clause | `LICENSE.mpmath.txt` |
| CPython | 3.13.16 | PSF-2.0 (Python-2.0) | `LICENSE.cpython.txt` |

CPython comes from the [python-build-standalone](https://github.com/astral-sh/python-build-standalone)
release `20261001`, a single executable with these libraries linked in:

| Library | License | Text |
|---|---|---|
| OpenSSL 3 | Apache-2.0 | `LICENSE.openssl-3.txt` |
| SQLite | Public domain | `LICENSE.sqlite.txt` |
| zlib | Zlib | `LICENSE.zlib.txt` |
| bzip2 | bzip2-1.0.6 | `LICENSE.bzip2.txt` |
| liblzma (XZ Utils) | 0BSD | `LICENSE.liblzma.txt` |
| libffi | MIT | `LICENSE.libffi.txt` |
| mpdecimal | BSD-2-Clause | `LICENSE.mpdecimal.txt` |
| Expat | MIT | `LICENSE.expat.txt` |
| libedit | BSD-3-Clause | `LICENSE.libedit.txt` |
| ncurses | X11 | `LICENSE.ncurses.txt` |
| libuuid | BSD-3-Clause | `LICENSE.libuuid.txt` |

The Tcl/Tk libraries and the `_tkinter` and `_dbm` modules of that release are removed at build
time and are not redistributed.
