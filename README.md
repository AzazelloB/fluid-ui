# fluid-ui

## Run on macOS

Install Odin dev-2026-11a or newer, the Vulkan loader, and MoltenVK. MoltenVK
provides Vulkan over Metal. If Odin is already installed through Homebrew,
`brew upgrade odin` updates it.

```sh
brew install odin vulkan-loader molten-vk
odin run examples/showcase -minimum-os-version:11.0
```

Append `-- --large-ui` to try the showcase with larger text and controls.
Append `-- --remote-navigation` to preview arrow-key focus navigation.
Use `-- --large-ui --remote-navigation` to combine them.

### Build a local macOS app

Install Odin, MoltenVK, and the Xcode command-line tools. The bundle includes the
graphics library and fonts and uses an ad hoc signature for local use.

```sh
brew install odin molten-vk
examples/showcase/macos/bundle.sh --install
open "$HOME/Applications/Bamboo Field Station.app"
```

Omit `--install` to build only `.build/showcase-macos/Bamboo Field Station.app`.

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

Pass `--large-ui` for a larger interface or `--remote-navigation` to
preview arrow-key focus navigation. The flags can be combined.
