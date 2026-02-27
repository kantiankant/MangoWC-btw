#!/usr/bin/env bash

WALLPAPER_DIR="$HOME/.config/mango/walls"
STATE_FILE="/tmp/swww_state"

# 1. Daemon Check
swww query >/dev/null 2>&1 || {
  swww-daemon &
  sleep 0.1
}

# 2. Get all images into an array safely (handles spaces and webp)
mapfile -t PICS < <(find "$WALLPAPER_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) | sort)

TOTAL_PICS=${#PICS[@]}
[[ $TOTAL_PICS -eq 0 ]] && echo "No wallpapers found" && exit 1

# 3. Get current index
CUR_IDX=$(cat "$STATE_FILE" 2>/dev/null || echo 0)

# Reset if out of bounds
if ((CUR_IDX >= TOTAL_PICS)); then
  CUR_IDX=0
fi

SELECTED="${PICS[$CUR_IDX]}"

# 4. Apply and Save Next Index
swww img "$SELECTED" --transition-type wipe --transition-angle 30 --transition-duration 0.5 --transition-fps 144

echo $(((CUR_IDX + 1) % TOTAL_PICS)) >"$STATE_FILE"
