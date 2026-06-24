#!/bin/bash
# Reinstala el codec WebP WIC en el prefijo de CMO (appid 1076160).
# Necesario si se recrea el prefijo o se actualiza GE-Proton y se pierde el registro.
# Arregla crashes WINCODEC_ERR_COMPONENTNOTFOUND (0x88982F50) al cargar escenarios
# con imagenes de unidad WebP (VP8/VP8X) que CMO extrae a Temp/ y carga via WIC.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
PFX="$HOME/.steam/debian-installation/steamapps/compatdata/1076160/pfx"
WINE="$HOME/.steam/root/compatibilitytools.d/GE-Proton10-34/files/bin/wine"
[ -f "$WINE" ] || { echo "No encuentro wine de GE-Proton10-34"; exit 1; }
cp "$HERE/WebpWICCodec.dll" "$PFX/drive_c/windows/system32/WebpWICCodec.dll" || exit 1
echo "DLL copiado a system32"
R(){ WINEPREFIX="$PFX" WINEDEBUG=-all "$WINE" reg add "$@" /reg:64 /f >/dev/null 2>&1; }
CAT='HKLM\Software\Classes\CLSID\{7ED96837-96F0-4812-B211-F13C24117ED3}\Instance\{C747A836-4884-47B8-8544-002C41BD63D2}'
DEC='HKLM\Software\Classes\CLSID\{C747A836-4884-47B8-8544-002C41BD63D2}'
R "$CAT" /v CLSID /d "{C747A836-4884-47B8-8544-002C41BD63D2}"
R "$CAT" /v FriendlyName /d "WebP Decoder"
R "$DEC" /ve /d "WebP Decoder"
R "$DEC" /v ContainerFormat /d "{E094B0E2-67F2-45B3-B0EA-115337CA7CF3}"
R "$DEC" /v FileExtensions /d ".webp"
R "$DEC" /v MimeTypes /d "image/webp"
R "$DEC" /v VendorGUID /d "{D4837961-2609-4B94-A9CB-A42A209AA021}"
R "$DEC\\Formats\\{6FDDC324-4E03-4BFE-B185-3D77768DC90F}" /ve /d ""
R "$DEC\\InProcServer32" /ve /d "C:\\windows\\system32\\WebpWICCodec.dll"
R "$DEC\\InProcServer32" /v ThreadingModel /d "Both"
R "$DEC\\Patterns\\0" /v Position /t REG_DWORD /d 0
R "$DEC\\Patterns\\0" /v Length /t REG_DWORD /d 12
R "$DEC\\Patterns\\0" /v Pattern /t REG_BINARY /d 524946460000000057454250
R "$DEC\\Patterns\\0" /v Mask /t REG_BINARY /d ffffffff00000000ffffffff
echo "Codec WebP WIC registrado (64-bit). Listo."
