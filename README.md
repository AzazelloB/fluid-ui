# fluid-ui

## Run on macOS

Install Odin, the Vulkan loader, and MoltenVK. MoltenVK provides Vulkan over Metal.

```sh
brew install odin vulkan-loader molten-vk
odin run examples/showcase -minimum-os-version:11.0
```

## Run on Windows (x64)

Install [Odin dev-2026-11a or newer](https://odin-lang.org/docs/install/), Visual Studio Build Tools with
**Desktop development with C++** and a Windows SDK, and a Vulkan-capable GPU
driver. Add the directory containing `odin.exe` to your `PATH`.

```powershell
$out = '.build\showcase-vulkan'
New-Item -ItemType Directory -Path $out -Force | Out-Null
odin build examples/showcase "-out:$out\showcase.exe" -o:speed -subsystem:windows
& "$out\showcase.exe"
```

The showcase uses the Vulkan loader installed by the graphics driver. Vulkan
shaders are embedded in the build. Presentation uses mailbox when the surface
offers it and falls back to FIFO otherwise.
