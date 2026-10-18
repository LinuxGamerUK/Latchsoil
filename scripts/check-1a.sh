#!/usr/bin/env bash
# Milestone 1a acceptance, the Godot half. The scene drives SimHost through the
# bridge (move, gather, eat) and asserts the snapshot, not a Rust-only result.
#
# Reasons the scene covers, by name: "no material", "no path".
# The other three reasons in the contract (hungry, wounded, night) are produced
# directly in the sim crate's Rust tests, because a scene cannot set hunger.
# This script does not fake them.
#
# Run from the repository root, either directly or via the devshell.
set -euo pipefail

root=$PWD
if [ ! -f "$root/godot/project.godot" ]; then
  echo "check-1a: run me from the repository root (no godot/project.godot here)" >&2
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
trap 'rm -f "$log"' EXIT

# Do not pipe this through head or tail: the pipeline status would hide godot's.
set +e
godot --headless --path "$root/godot" res://scenes/harness.tscn >"$log" 2>&1
status=$?
set -e

cat "$log"

if [ "$status" -ne 0 ]; then
  echo "check-1a: godot exited $status" >&2
  exit 1
fi

if ! grep -qx '1a: ok' "$log"; then
  echo "check-1a: 1a: ok is missing from the output" >&2
  exit 1
fi

if grep -qE 'SCRIPT ERROR|ERROR: Cannot get class|ObjectDB instance was leaked' "$log"; then
  echo "check-1a: the engine logged an error while loading the extension" >&2
  exit 1
fi

echo "check-1a: ok"
