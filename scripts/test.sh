#!/usr/bin/env bash
# Milestone 0 acceptance, both halves: the sim's own tests with no engine in the
# process, then the headless Godot load. This is what CI runs.
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
