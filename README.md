# fluid-ui

## Run on macOS

```sh
brew install odin sdl3 sdl3_ttf
odin run examples/showcase
```

If the linker cannot find the Homebrew libraries on Apple Silicon:

```sh
odin run examples/showcase -extra-linker-flags:"-L/opt/homebrew/lib -Wl,-rpath,/opt/homebrew/lib"
```
