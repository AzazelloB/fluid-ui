# fluid-ui

## Run on macOS

```sh
brew install odin sdl3 sdl3_ttf
odin run examples/showcase -minimum-os-version:11.0
```

The explicit deployment target prevents the linker from assigning a newer macOS requirement.

If the linker cannot find the Homebrew libraries on Apple Silicon:

```sh
odin run examples/showcase -minimum-os-version:11.0 -extra-linker-flags:"-L/opt/homebrew/lib -Wl,-rpath,/opt/homebrew/lib"
```

## Run on Windows (x64)

Install Visual Studio Build Tools with the **Desktop development with C++**
workload and a Windows SDK. Add the directory containing `odin.exe` to your
`PATH`. The build below uses [Odin dev-2026-11a for Windows x64](https://github.com/odin-lang/Odin/releases/tag/dev-2026-11a),
which includes the SDL3 and SDL3_ttf bindings and DLLs.

Run these commands from the repository root in PowerShell.

```powershell
$out = '.build\showcase-win-x64'
$sdl = Join-Path (odin root) 'vendor\sdl3'
New-Item -ItemType Directory -Path $out -Force | Out-Null
odin build examples/showcase "-out:$out\showcase.exe" -o:speed -subsystem:windows
Copy-Item -LiteralPath "$sdl\SDL3.dll", "$sdl\ttf\SDL3_ttf.dll" -Destination $out
& "$out\showcase.exe"
```

For an existing build, open `showcase.exe` with both DLLs in the same directory.
