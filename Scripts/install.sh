#!/bin/bash
#
# Update the installed app after a code change: rebuild Perch.app, quit the running
# copy, replace /Applications/Perch.app in place, and relaunch. Run from anywhere:
#   ./Scripts/install.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="/Applications/Perch.app"

# Build the bundle (Scripts/build-app.sh produces ./Perch.app).
./Scripts/build-app.sh

echo "Quitting running Perch (if any)..."
osascript -e 'quit app "Perch"' 2>/dev/null || true
pkill -x Perch 2>/dev/null || true
sleep 1

echo "Installing to ${DEST}..."
rm -rf "${DEST}"
cp -R Perch.app "${DEST}"
rm -rf Perch.app

open "${DEST}"
echo "Updated and relaunched ${DEST}"
echo "If 'Launch at Login' stops working after an update, toggle it off then on once."
