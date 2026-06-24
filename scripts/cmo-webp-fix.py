#!/usr/bin/env python3
"""
cmo-webp-fix: vigila la carpeta Temp/ de Command: Modern Operations y convierte
las imagenes de unidad que CMO extrae en formato WebP VP8X (que el WIC de Wine
NO decodifica -> crash WINCODEC_ERR_COMPONENTNOTFOUND 0x88982F50) a WebP VP8
simple, depositandolas en DB/Images/DB3000. Asi, en el siguiente lanzamiento,
CMO carga la imagen desde la carpeta (decoder propio, VP8 OK) y no recurre al
VP8X de respaldo. Cada unidad se "cura" una vez.

No toca nada online ni el prefijo de Wine. Solo lee Temp/ y escribe en DB/Images.
"""
import os, glob, subprocess, time, sys

CMO = os.path.expanduser(
    "~/.steam/debian-installation/steamapps/common/Command - Modern Operations")
TEMP = os.path.join(CMO, "Temp")
DEST = os.path.join(CMO, "DB", "Images", "DB3000")
POLL = 0.5

def chunk_type(path):
    try:
        with open(path, "rb") as f:
            head = f.read(16)
        if head[0:4] == b"RIFF" and head[8:12] == b"WEBP":
            return head[12:16].decode("ascii", "replace")
    except Exception:
        return None
    return None

def convert(src, dst):
    tmp = dst + ".tmp"
    r = subprocess.run(
        ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
         "-i", src, "-c:v", "libwebp", "-lossless", "0", "-q:v", "92",
         "-f", "webp", tmp],
        capture_output=True)
    if r.returncode == 0 and os.path.exists(tmp) and os.path.getsize(tmp) > 0:
        os.replace(tmp, dst)
        return True
    if os.path.exists(tmp):
        os.remove(tmp)
    sys.stderr.write("ffmpeg fallo en %s: %s\n" % (src, r.stderr.decode("utf-8", "replace")[:200]))
    return False

def main():
    seen = {}  # src -> mtime ya procesado
    print("cmo-webp-fix vigilando %s -> %s" % (TEMP, DEST), flush=True)
    while True:
        for src in glob.glob(os.path.join(TEMP, "Process_*", "*.webp")):
            try:
                mt = os.path.getmtime(src)
            except OSError:
                continue
            if seen.get(src) == mt:
                continue
            seen[src] = mt
            if chunk_type(src) != "VP8X":
                continue
            name = os.path.basename(src)
            dst = os.path.join(DEST, name)
            # solo si falta en la carpeta (no pisar lo que ya este bien)
            if os.path.exists(dst) and chunk_type(dst) == "VP8 ":
                continue
            if convert(src, dst):
                print("convertido %s -> carpeta (VP8)" % name, flush=True)
        time.sleep(POLL)

if __name__ == "__main__":
    main()
