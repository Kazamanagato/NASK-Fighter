# NASK Fighter

Photo mode HUD for **Street Fighter 6**, made with [REFramework](https://github.com/praydog/REFramework).

HUD de modo foto para **Street Fighter 6**, feito com REFramework.

Credits, licenses and usage notes / Créditos, licenças e avisos: [`licenses/README.txt`](licenses/README.txt)

---

## Repository / Repositório

| Path | What it is |
|---|---|
| `reframework/autorun/NASK_Fighter.lua` + `NASK_Fighter/*.lua` | The mod (plain Lua) |
| `plugin_src/nask_capture.cpp` | Full source of `nask_capture.dll` (screenshot plugin) |
| `.github/workflows/build.yml` | GitHub builds the DLL from this source |
| `reframework/plugins/reframework-d2d.dll` | [reframework-d2d](https://github.com/cursey/reframework-d2d) by cursey (MIT), unmodified |
| `MMDK Update/` | Fix for alphaZomega's MMDK 1.0.7 (MIT, see `LICENSE_MMDK.txt`) |
| `licenses/` | Credits and third-party licenses |

`nask_capture.dll` is not stored here as a binary: download it from **Releases**, or from the **Actions** tab, where GitHub builds it from `plugin_src/`.

## nask_capture.dll

The Lua script talks to it only through JSON files in `reframework/data/NASK_Fighter/`. It does three things:

1. **capture**: copies the current frame (DirectX 12) and saves a PNG in the chosen photo folder (default `Pictures\NASK Fighter`), plus a gallery thumbnail in `reframework/images/nask_thumbs/`.
2. **open**: opens a file or folder in Windows Explorer.
3. **pick_dir**: shows the Windows folder picker.

No internet access, no other files read, nothing related to online play.

### Verify / Conferir

1. **Actions** tab → latest *Build nask_capture.dll* run → the **SHA-256** step shows the hash.
2. In PowerShell: `Get-FileHash nask_capture.dll` on the DLL you downloaded. Both hashes must match.

### Build it yourself (Visual Studio 2022 + CMake)

```
mkdir plugin_src\include\reframework
:: copy API.h (REFramework/include/reframework) and stb_image_write.h (nothings/stb) there
cmake -S plugin_src -B build -A x64
cmake --build build --config Release
```

## License

NASK Fighter's own code: MIT (`LICENSE`). Third-party parts keep their own licenses.
