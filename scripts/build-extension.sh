#!/usr/bin/env bash
# Build the GDExtension and put it where the Godot project loads it from.
# Every headless check and every export starts here, so the library path in
# godot/latchsoil.gdextension stays inside the project tree (res://bin/).
set -euo pipefail

root=$PWD
if [ ! -f "$root/rust/Cargo.toml" ]; then
  echo "build-extension: run me from the repository root (no rust/Cargo.toml here)" >&2
  exit 2
fi

profile=${1:-debug}
case "$profile" in
  debug) cargo_flags="" ;;
  release) cargo_flags="--release" ;;
  *)
    echo "build-extension: profile must be debug or release" >&2
    exit 2
    ;;
esac

cargo build --manifest-path "$root/rust/Cargo.toml" -p latchsoil-godot $cargo_flags

mkdir -p "$root/godot/bin"
ln -sf "$root/rust/target/$profile/liblatchsoil_godot.so" \
       "$root/godot/bin/liblatchsoil_godot.so"
echo "build-extension: linked $profile library into godot/bin/"
