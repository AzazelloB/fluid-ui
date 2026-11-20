#!/bin/bash
set -euo pipefail

install_app=false
case "${1:-}" in
    "") ;;
    --install) install_app=true ;;
    *) echo "Usage: $0 [--install]" >&2; exit 2 ;;
esac
if [[ $# -gt 1 ]]; then
    echo "Usage: $0 [--install]" >&2
    exit 2
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$script_dir/../../.."
output_dir="$PWD/.build/showcase-macos"
app_name="Bamboo Field Station.app"
moltenvk_prefix="$(brew --prefix molten-vk)"
moltenvk_library="$moltenvk_prefix/lib/libMoltenVK.dylib"
if [[ ! -f "$moltenvk_library" ]]; then
    echo "Install MoltenVK with brew install molten-vk." >&2
    exit 1
fi

# The bundle requires the newer of the executable and library deployment targets.
odin_minimum=11.0
library_minimum="$(xcrun vtool -arch "$(uname -m)" -show-build "$moltenvk_library" | awk '$1 == "minos" { print $2 }')"
if [[ -z "$library_minimum" ]]; then
    echo "Cannot read the MoltenVK macOS deployment target." >&2
    exit 1
fi
minimum_os="$(printf '%s\n' "$odin_minimum" "$library_minimum" | sort -t . -k 1,1n -k 2,2n -k 3,3n | tail -n 1)"

mkdir -p "$output_dir"
stage="$(mktemp -d "$output_dir/.bundle.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/$app_name"
contents="$app/Contents"
resources="$contents/Resources"
iconset="$stage/AppIcon.iconset"
mkdir -p "$contents/MacOS" "$contents/Frameworks" "$resources/Licenses" "$iconset"

odin build examples/showcase -o:speed "-minimum-os-version:$odin_minimum" "-out:$contents/MacOS/showcase"
install -m 755 "$moltenvk_library" "$contents/Frameworks/libMoltenVK.dylib"
cp "$moltenvk_prefix/LICENSE" "$resources/Licenses/MoltenVK.txt"
cp examples/showcase/assets/BricolageGrotesque-OFL.txt "$resources/Licenses/"
cp "$script_dir/Info.plist" "$contents/Info.plist"
plutil -insert LSMinimumSystemVersion -string "$minimum_os" "$contents/Info.plist"

for size in 16 32 128 256 512; do
    retina=$((size * 2))
    sips -z "$size" "$size" "$script_dir/AppIcon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z "$retina" "$retina" "$script_dir/AppIcon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns -o "$resources/AppIcon.icns" "$iconset"

codesign --force --sign - "$contents/Frameworks/libMoltenVK.dylib"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"

ditto "$app" "$output_dir/$app_name"
printf 'Built %s\n' "$output_dir/$app_name"

if $install_app; then
    mkdir -p "$HOME/Applications"
    destination="$HOME/Applications/$app_name"
    if [[ -e "$destination" || -L "$destination" ]]; then
        bundle_id="$(plutil -extract CFBundleIdentifier raw "$contents/Info.plist")"
        if [[ -L "$destination" ]] || [[ "$(plutil -extract CFBundleIdentifier raw "$destination/Contents/Info.plist" 2>/dev/null)" != "$bundle_id" ]]; then
            echo "An unrelated item already exists at $destination." >&2
            exit 1
        fi
    fi
    ditto "$app" "$destination"
    codesign --verify --deep --strict "$destination"
    printf 'Installed %s\n' "$destination"
fi
