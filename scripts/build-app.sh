#!/bin/zsh
# Builds build/Rotatorring.app (release) and signs it.
# A stable signing identity keeps the Screen Recording permission across rebuilds;
# set SIGN_IDENTITY to override (use "-" for ad-hoc signing).
set -euo pipefail
cd "${0:A:h}/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Rotatorring"

APP=build/Rotatorring.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Rotatorring"
cp apps/macos/Resources/Info.plist "$APP/Contents/Info.plist"
cp apps/macos/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  SIGN_IDENTITY=$(security find-identity -p codesigning -v 2>/dev/null \
    | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)
  : "${SIGN_IDENTITY:=-}"
fi
codesign --force --sign "$SIGN_IDENTITY" "$APP"
echo "Built $APP (signed with: $SIGN_IDENTITY)"
