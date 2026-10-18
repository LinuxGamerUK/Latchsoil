#!/usr/bin/env bash
# Milestone 0 acceptance, the Godot half: the engine loads the extension, the sim
# advances one tick, one line is printed, and the process exits 0.
#
# Run from the repository root, either directly or as `nix run .#smoke`.
set -euo pipefail

root=$PWD
if [ ! -f "$root/godot/project.godot" ]; then
  echo "smoke: run me from the repository root (no godot/project.godot here)" >&2
  exit 2
fi

"$root/scripts/build-extension.sh"

# A game run does not scan for .gdextension files on its own: Godot loads what
# .godot/extension_list.cfg names, and only the editor writes that file (during
# import). A fresh checkout therefore starts with no extension at all, so this
# script writes the one line itself. `--import` writes it too, but the headless
# editor aborts after its first pass, so its exit code is not usable here.
mkdir -p "$root/godot/.godot"
printf 'res://latchsoil.gdextension\n' >"$root/godot/.godot/extension_list.cfg"

log=$(mktemp)
set +e
godot --headless --path "$root/godot" res://scenes/smoke.tscn >"$log" 2>&1
status=$?
set -e

cat "$log"
if [ "$status" -ne 0 ]; then
  echo "smoke: godot exited $status" >&2
  rm -f "$log"
  exit 1
fi

if ! grep -qE '^latchsoil: tick [0-9]+ hash [0-9a-f]{16}$' "$log"; then
  echo "smoke: the sim's tick line is missing from the output" >&2
  rm -f "$log"
  exit 1
fi

if grep -qE 'SCRIPT ERROR|ERROR: Cannot get class|ObjectDB instance was leaked' "$log"; then
  echo "smoke: the engine logged an error while loading the extension" >&2
  rm -f "$log"
  exit 1
fi

rm -f "$log"
echo "smoke: ok"
