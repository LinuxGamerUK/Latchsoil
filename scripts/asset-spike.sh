#!/usr/bin/env bash
# Generate one named prop as a .glb with headless Blender.
#
# No display, no GPU driver, and no X server are required. Blender comes from
# nixpkgs via `nix shell`; it is not part of the game devshell.
#
# Usage, from the repository root:
#   scripts/asset-spike.sh <name>
#
# The generator is scripts/gen_<name>.py. It receives the output path after --.
# The mesh is written to godot/assets/<name>.glb. Godot still has to import it
# before a scene can load it; this script only builds the file.
set -euo pipefail

root=$PWD
name=${1:-}

if [ -z "$name" ] || [ "$name" = "-h" ] || [ "$name" = "--help" ]; then
  echo "usage: scripts/asset-spike.sh <name>" >&2
  echo "  generator: scripts/gen_<name>.py" >&2
  echo "  writes:    godot/assets/<name>.glb" >&2
  exit 2
fi

# A name is a filename stem, not a path. Reject anything that could escape assets/.
case "$name" in
  *[!a-z0-9_-]*)
    echo "asset-spike: name must be lowercase letters, digits, '_' or '-'" >&2
    exit 2
    ;;
esac

if [ ! -f "$root/godot/project.godot" ]; then
  echo "asset-spike: run me from the repository root (no godot/project.godot here)" >&2
  exit 2
fi

gen="$root/scripts/gen_${name}.py"
if [ ! -f "$gen" ]; then
  echo "asset-spike: no generator at scripts/gen_${name}.py" >&2
  exit 2
fi

mkdir -p "$root/godot/assets"
out="$root/godot/assets/${name}.glb"

start=$(date +%s.%N)
set +e
nix shell nixpkgs#blender -c blender --background --factory-startup \
  --python "$gen" -- "$out"
status=$?
set -e
end=$(date +%s.%N)
elapsed=$(python3 -c "print(round(${end} - ${start}, 3))")

if [ "$status" -ne 0 ]; then
  echo "asset-spike: blender exited ${status} after ${elapsed}s" >&2
  exit 1
fi
if [ ! -s "$out" ]; then
  echo "asset-spike: blender exited ${status} but wrote no file at godot/assets/${name}.glb" >&2
  exit 1
fi

bytes=$(wc -c <"$out" | tr -d ' ')
echo "asset-spike: wrote godot/assets/${name}.glb (${bytes} bytes) in ${elapsed}s, blender exit ${status}"
