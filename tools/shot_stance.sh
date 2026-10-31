#!/usr/bin/env bash
# Records tools/stance_strip.gd and cuts a contact sheet to out/stance_<tag>.png (run from the repository root).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p out
tag=${1:-now}
timeout 300 xvfb-run -a godot --path . --resolution 960x540 --fixed-fps 30 --write-movie out/stance.avi \
  --script res://tools/stance_strip.gd 2>&1 | grep -E "STANCE|ERROR|SCRIPT" || true
ffmpeg -v error -y -i out/stance.avi -vf "fps=6,crop=ih*0.8:ih*0.8,scale=200:200,tile=8x5" -frames:v 1 "out/stance_$tag.png"
rm -f out/stance.avi
