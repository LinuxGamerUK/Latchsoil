#!/usr/bin/env bash
# Render one frame of a scene to a PNG on a host with no display and no GPU
# driver: software Vulkan (lavapipe) under Xvfb.
#
# The scene must cooperate: when LATCHSOIL_SCREENSHOT is set it saves its own
# viewport to that path after LATCHSOIL_SCREENSHOT_FRAMES frames and quits.
# The scene owns the picture; this script owns the environment.
#
# Usage, from the repository root:
#   scripts/render.sh [scene] [out.png] [width] [height]
set -euo pipefail

root=$PWD
scene=${1:-res://scenes/main.tscn}
out=${2:-$root/renders/frame.png}
width=${3:-1280}
height=${4:-720}

if [ ! -f "$root/godot/project.godot" ]; then
  echo "render: run me from the repository root (no godot/project.godot here)" >&2
  exit 2
fi

"$root/scripts/build-extension.sh"

# Nixpkgs gives the three pieces this host lacks: a display, a Vulkan ICD, and
# the loader Godot dlopens. Nothing here is machine-specific.
mesa=$(nix-build '<nixpkgs>' -A mesa --no-out-link)
loader=$(nix-build '<nixpkgs>' -A vulkan-loader --no-out-link)
xvfb=$(nix-build '<nixpkgs>' -A xvfb --no-out-link)

mkdir -p "$(dirname "$out")" "$root/godot/.godot"
printf 'res://latchsoil.gdextension\n' >"$root/godot/.godot/extension_list.cfg"

display=:98
"$xvfb/bin/Xvfb" "$display" -screen 0 "${width}x${height}x24" -ac +extension GLX +render -noreset &
xvfb_pid=$!
trap 'kill "$xvfb_pid" 2>/dev/null || true' EXIT
sleep 1

export DISPLAY="$display"
export VK_ICD_FILENAMES="$mesa/share/vulkan/icd.d/lvp_icd.x86_64.json"
export VK_DRIVER_FILES="$VK_ICD_FILENAMES"
export LD_LIBRARY_PATH="$loader/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LATCHSOIL_SCREENSHOT="$out"
export LATCHSOIL_SCREENSHOT_FRAMES="${LATCHSOIL_SCREENSHOT_FRAMES:-30}"
unset WAYLAND_DISPLAY

set +e
godot --path "$root/godot" "$scene" \
  --display-driver x11 --rendering-driver vulkan --rendering-method forward_plus \
  --audio-driver Dummy --resolution "${width}x${height}" --disable-vsync \
  --quit-after 240
status=$?
set -e

if [ "$status" -ne 0 ]; then
  echo "render: godot exited $status" >&2
  exit 1
fi
if [ ! -s "$out" ]; then
  echo "render: the scene did not write $out (is LATCHSOIL_SCREENSHOT honoured?)" >&2
  exit 1
fi

echo "render: wrote $out"
