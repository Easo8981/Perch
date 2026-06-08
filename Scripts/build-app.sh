#!/bin/bash
#
# Build Perch.app -- a real, ad-hoc-signed .app bundle you can move to /Applications
# and register as a login item (right-click the shelf > Launch at Login).
#
set -euo pipefail
cd "$(dirname "$0")/.."

APP="Perch.app"
CONFIG="release"

echo "Building (${CONFIG})..."
swift build -c "${CONFIG}"
BIN=".build/${CONFIG}/Perch"

echo "Assembling ${APP}..."
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/Perch"
cp Resources/Info.plist "${APP}/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "${APP}/Contents/Resources/AppIcon.icns"
else
  echo "  (no Resources/AppIcon.icns -- run 'swift Scripts/make-icon.swift' for a custom icon)"
fi

# Ad-hoc code signature -- required for SMAppService login-item registration.
echo "Signing (ad-hoc)..."
codesign --force --deep --sign - "${APP}"

echo "Built ${APP}"
echo "Move it to /Applications (so the login-item path stays stable), then launch it"
echo "and toggle 'Launch at Login' from the shelf's right-click menu."
