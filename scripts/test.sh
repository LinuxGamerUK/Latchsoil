#!/usr/bin/env bash
# The acceptance gate: the sim's own tests with no engine in the process, then
# the headless Godot checks — the milestone 0 load, the milestone 1a orders,
# the milestone 1b buildings, craft, haul and save, and the milestone 2 body.
# This is what CI runs.
#
# Run from the repository root, either directly or as `nix run .#test`.
set -euo pipefail

root=$PWD
if [ ! -f "$root/rust/Cargo.toml" ]; then
  echo "test: run me from the repository root (no rust/Cargo.toml here)" >&2
  exit 2
fi

echo "== cargo test (no Godot process) =="
cargo test --manifest-path "$root/rust/Cargo.toml"

echo
echo "== headless Godot: extension load, one tick, quit =="
"$root/scripts/smoke.sh"

echo
echo "== headless Godot: milestone 1a orders, paths and failure reasons =="
"$root/scripts/check-1a.sh"

echo
echo "== headless Godot: milestone 1b buildings, craft, haul and save =="
"$root/scripts/check-1b.sh"

echo
echo "== headless Godot: milestone 2 body, skills and save =="
"$root/scripts/check-2.sh"
