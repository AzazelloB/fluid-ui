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
