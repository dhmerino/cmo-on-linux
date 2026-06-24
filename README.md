# Command: Modern Operations on Linux, fully working (briefings + crashes fixed)

A complete, battle-tested recipe to run **Command: Modern Operations** (Steam appid
**1076160**) on Linux via Proton, **including the blank briefing panels** and the
**scenario-load crashes** that nobody seems to have documented.

CMO is notoriously hard on Linux because it leans on **four** different Windows
subsystems, each needing its own fix:

| Symptom | Root cause | Fix |
|---|---|---|
| Instant crash on **Play** | Obfuscated .NET; wine-mono throws `Invalid IL code` | Native **.NET Framework 4.8** |
| **Mission-start briefing** + info popups blank | Renders via **WebView2** (Chromium) | WebView2 109 + win7 mode |
| **Side briefing** + DB viewer blank | Renders via legacy **MSHTML/IE engine** | **IE8** |
| **Crash loading scenarios/tutorials** (e.g. Air Warfare 1, Submarine 1.3) | Wine's WIC has **no WebP decoder**; unit pictures load via WIC | **Custom WebP WIC codec** (this repo) |

The last one is the original contribution here: a from-scratch **WebP WIC decoder
DLL** built for Wine, because the crash (`WINCODEC_ERR_COMPONENTNOTFOUND`,
`0x88982F50`) is otherwise unsolvable.

Tested on Ubuntu 22.04 + NVIDIA GTX 1060, GE-Proton10-34. Should apply to any
modern distro, but let me know.

---

## TL;DR

```
GE-Proton  +  dotnet48  +  ie8  +  WebView2 109  +  the WebP WIC codec in this repo
```

If your game already launches and only crashes when loading scenarios, you only
need **[the WebP codec](#5-webp-wic-codec--fixes-scenario-load-crashes)**.

---

## 0. Tools

```bash
pip install --user protontricks
curl -fsSL https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks \
  -o ~/.local/bin/winetricks && chmod +x ~/.local/bin/winetricks
sudo apt install cabextract mingw-w64    # mingw-w64 only if you build the codec
```

## 1. Use GE-Proton, not vanilla Proton

Vanilla Proton "Experimental"/"Hotfix" are Wine 11, and the .NET 4.x installer
fails there with `err:msi:extract_cabinet FDICopy failed`. Use **GE-Proton 9.x or
10.x** (Wine 9/10). This guide uses **GE-Proton10-34**.

Drop it in `~/.steam/root/compatibilitytools.d/`, restart Steam, then right-click
CMO → Properties → Compatibility → force GE-Proton. Launch once to create the
prefix, then quit.

## 2. Native .NET 4.8 — fixes the instant crash on "Play"

CMO's code is obfuscated; wine-mono's JIT throws `System.InvalidProgramException:
Invalid IL code`. You need the real Microsoft .NET Framework.

**Gotcha:** Proton pre-registers .NET 4.7 as "already installed", so the installer
skips the file copy. Delete those keys first:

```bash
protontricks-launch --appid 1076160 reg delete "HKLM\Software\Microsoft\NET Framework Setup\NDP\v4" /f
protontricks-launch --appid 1076160 reg delete "HKLM\Software\Wow6432Node\Microsoft\NET Framework Setup\NDP\v4" /f
protontricks 1076160 dotnet48
```

Verify: `.../compatdata/1076160/pfx/drive_c/windows/Microsoft.NET/Framework64/v4.0.30319/clr.dll`
should exist.

## 3. WebView2 — fixes the mission-start briefing + info popups

Install **WebView2 Runtime 109.0.1518.78** (newer evergreen installers fail under
Wine; 109 is the sweet spot, mirrored on archive.org):

```bash
protontricks-launch --appid 1076160 ~/Downloads/MicrosoftEdgeWebView2RuntimeInstallerX64.exe /silent /install
protontricks-launch --appid 1076160 reg add "HKCU\Software\Wine\AppDefaults\msedgewebview2.exe" /v Version /t REG_SZ /d win7 /f
```

(If panels stay blank, force software rendering:
`HKCU\Environment\WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = --no-sandbox --disable-gpu`.)

## 4. IE8 — fixes the blank side briefing & database viewer

The side briefing throws `Unknown MSHTML Error: The method or operation is not
implemented` because it uses the **legacy IE/MSHTML engine**, and Wine's built-in
MSHTML is incomplete. Install a real Trident engine:

```bash
protontricks 1076160 ie8
```

## 5. WebP WIC codec — fixes scenario-load crashes

**Symptom:** the game launches and the menus work, but loading certain scenarios
or tutorials crashes every time. The exception log shows, repeatedly:

```
Exception Type: System.Runtime.InteropServices.COMException
Message: Exception from HRESULT: 0x88982F50      // WINCODEC_ERR_COMPONENTNOTFOUND
```

**Root cause (the deep version).** CMO ships only a partial set of unit pictures in
`DB/Images/DB3000/`. Pictures present there load through CMO's *own* WebP decoder
and work fine. Pictures **missing** there are extracted on demand to
`Temp/Process_<PID>/<Type>_<id>.webp` and loaded through **WIC** (Windows Imaging
Component) — and **Wine's WIC has no WebP decoder registered at all**. So the load
returns `COMPONENTNOTFOUND` and the game crashes. (The VP8 vs VP8X format is a red
herring; the real split is the *load path*: folder = CMO's decoder, Temp = WIC.)

**Fix.** Register a real WebP WIC decoder in the prefix. This repo ships one built
from `webmproject/webp-wic-codec` + modern libwebp, with two changes required under
Wine:

1. **Register in the native 64-bit view** (`reg add ... /reg:64`). A plain
   `regedit` import lands the keys under `Wow6432Node` (32-bit), where the 64-bit
   WIC never looks.
2. **`Seek(0)` in `ParseHeader`.** Wine's WIC does **not** rewind the stream after
   pattern-matching, so the decoder is handed the stream positioned at the inner
   RIFF chunk (offset 12) instead of the file start. libwebp tolerates a bare
   `VP8 ` chunk but not `VP8X`, so extended/alpha images fail. Seeking to 0 fixes
   it. (See `webp-wic-codec/build.sh` for the exact patch.)

### Install (prebuilt binary)

```bash
cd webp-wic-codec
sha256sum -c WebpWICCodec.dll.sha256     # optional: verify the binary
./install.sh                             # copies the DLL into the prefix and registers it (64-bit)
```

`install.sh` targets the default Steam prefix
(`~/.steam/debian-installation/steamapps/compatdata/1076160/pfx`) and GE-Proton10-34;
edit the paths at the top if yours differ.

### Build it yourself

```bash
sudo apt install mingw-w64 git
cd webp-wic-codec
./build.sh          # clones sources, applies the Wine patches, produces WebpWICCodec.dll
./install.sh
```

Re-run `install.sh` if you ever recreate the prefix or a Proton update wipes the
registration.

---

## Result

Game launches, **all** briefings render (WebView2 + MSHTML), graphics run
D3D11 → DXVK → Vulkan, and **scenarios/tutorials load without crashing**. Fully
playable.

## Notes / FAQ

- **Multiplayer** is Professional-Edition only. For the standard edition, use
  community PBEM/hotseat via [IKE](https://github.com/musurca/IKE).
- **Why not just convert the images?** The missing pictures come compressed inside
  the `.db3` databases, extracted at runtime — you can't pre-convert them cleanly.
  Fixing WIC fixes every scenario at once.
- **The codec is generic.** Any Wine/Proton app that loads `.webp` through WIC and
  hits `0x88982F50` can use the same DLL + `install.sh` (adjust the prefix path).

## Credits & license

- This guide and scripts: **BSD-3-Clause** (see `LICENSE`).
- WebP WIC codec: derived from
  [webmproject/webp-wic-codec](https://github.com/webmproject/webp-wic-codec) and
  [libwebp](https://chromium.googlesource.com/webm/libwebp), © Google Inc., BSD-3-Clause
  + patent grant. See `webp-wic-codec/THIRD_PARTY_NOTICES.txt`.

o7
