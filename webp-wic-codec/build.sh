#!/bin/bash
# Build a WebP WIC decoder DLL (64-bit) that works under Wine/Proton.
#
# Why: Wine's windowscodecs ships NO usable WebP WIC decoder, so any program
# that loads .webp through WIC (e.g. Command: Modern Operations' unit pictures)
# fails with WINCODEC_ERR_COMPONENTNOTFOUND (0x88982F50) and crashes.
#
# This compiles webmproject/webp-wic-codec against a modern libwebp with
# mingw-w64, applying two fixes needed under Wine (see PATCHES below).
#
# Requires: mingw-w64, git.   Output: ./WebpWICCodec.dll
set -euo pipefail

CCC=x86_64-w64-mingw32-gcc
CXX=x86_64-w64-mingw32-g++
command -v "$CCC" >/dev/null || { echo "Install mingw-w64 first (e.g. sudo apt install mingw-w64)"; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
echo ">> work dir: $WORK"
cd "$WORK"

# Pinned codec commit (last upstream commit; repo is a read-only mirror).
git clone https://github.com/webmproject/webp-wic-codec codec
git -C codec checkout -q b9b11aeb104027ea0874f66fc266c414c6b28dc8
# Modern libwebp (only the stable public decode API is used, so HEAD is fine).
git clone --depth 1 https://chromium.googlesource.com/webm/libwebp

SRC="$WORK/codec/src"

# ---- PATCHES (applied with python so they're CRLF/line-ending agnostic) ----
python3 - "$SRC" <<'PY'
import sys, re
src = sys.argv[1]

# 1) uuid.h: drop the codec's GUID_ContainerFormatWebp; mingw's wincodec.h
#    already defines it (standard Windows WebP container GUID).
p = src + "/uuid.h"; s = open(p, encoding="latin-1").read()
s = re.sub(r'^DEFINE_GUID\(GUID_ContainerFormatWebp,',
           r'//DEFINE_GUID(GUID_ContainerFormatWebp,', s, flags=re.M)
open(p, "w", encoding="latin-1").write(s)

# 2) main.cpp: mingw's advpub.h only has STRTABLE/STRENTRY (no ...A variants),
#    and doesn't define the SAL __in macro used in the DllMain signature.
p = src + "/main.cpp"; s = open(p, encoding="latin-1").read()
s = s.replace("STRTABLEA", "STRTABLE").replace("STRENTRYA", "STRENTRY")
s = s.replace(
    "BOOL WINAPI DllMain(__in  HINSTANCE hinstDLL, __in  DWORD fdwReason, __in  LPVOID lpvReserved)",
    "BOOL WINAPI DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpvReserved)")
open(p, "w", encoding="latin-1").write(s)

# 3) decode_container.cpp: THE KEY WINE FIX. Wine's WIC does not rewind the
#    stream after pattern-matching, so the decoder receives it positioned at
#    the inner chunk (offset 12) instead of the RIFF header. libwebp tolerates
#    a bare "VP8 " chunk but not "VP8X" -> extended/alpha images fail to decode.
#    Force the stream to position 0 at the start of ParseHeader.
p = src + "/decode_container.cpp"; s = open(p, encoding="latin-1").read()
anchor = "  if (FAILED(ret = pIStream->Read(header, sizeof(header), &read)))"
seek = ("  // Wine does not rewind the stream after WIC pattern-matching; the\n"
        "  // decoder must seek back to the start of the file itself.\n"
        "  { LARGE_INTEGER z; z.QuadPart = 0; pIStream->Seek(z, STREAM_SEEK_SET, NULL); }\n")
assert anchor in s, "anchor not found in decode_container.cpp"
s = s.replace(anchor, seek + anchor, 1)
open(p, "w", encoding="latin-1").write(s)
print("patches applied")
PY

# ---- compile ----
CF="-O2 -msse4.1 -DNDEBUG -I$WORK/libwebp -I$WORK/libwebp/src"
XF="$CF -I$SRC -std=gnu++14 -fpermissive"
objs=()
for c in "$WORK"/libwebp/src/{dec,dsp,utils,sharpyuv}/*.c; do
  [ -f "$c" ] || continue
  o="$WORK/$(echo "$c" | tr '/' '_').o"
  $CCC $CF -c "$c" -o "$o"; objs+=("$o")
done
for cpp in main.cpp decode_container.cpp decode_frame.cpp; do
  o="$WORK/$cpp.o"; $CXX $XF -c "$SRC/$cpp" -o "$o"; objs+=("$o")
done
$CXX -shared -static -static-libgcc -static-libstdc++ \
  -o "$HERE/WebpWICCodec.dll" "${objs[@]}" "$SRC/webp_wic_codec.def" \
  -lole32 -loleaut32 -luuid -ladvapi32 -lshlwapi -lshell32 -lgdi32

echo ">> built: $HERE/WebpWICCodec.dll"
sha256sum "$HERE/WebpWICCodec.dll"
rm -rf "$WORK"
