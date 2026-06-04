#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="NextMeetingBar"
BUNDLE="${APP_NAME}.app"
# Stable self-signed identity so TCC (calendar access) survives rebuilds.
# Create once: Keychain Access > Certificate Assistant > Create a Certificate
#   Name: "NextMeetingBar Dev", Identity Type: Self-Signed Root, Type: Code Signing
SIGN_IDENTITY="NextMeetingBar Dev"

echo "[1/3] Building (release)..."
swift build -c release

echo "[2/3] Assembling ${BUNDLE}..."
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS"
cp ".build/release/${APP_NAME}" "${BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Info.plist" "${BUNDLE}/Contents/Info.plist"

echo "[3/3] Signing..."
if security find-identity -v -p codesigning | grep -q "${SIGN_IDENTITY}"; then
    echo "      using stable identity '${SIGN_IDENTITY}' (calendar grant persists)"
    codesign --force --deep --sign "${SIGN_IDENTITY}" "${BUNDLE}"
else
    echo "      WARNING: identity '${SIGN_IDENTITY}' not found - falling back to ad-hoc."
    echo "      TCC will re-prompt for calendar access on every rebuild until you create it:"
    echo "      Keychain Access > Certificate Assistant > Create a Certificate"
    echo "      (Self-Signed Root, Code Signing), name it '${SIGN_IDENTITY}'."
    codesign --force --deep --sign - "${BUNDLE}"
fi

echo "Done. Launch with:  open ${BUNDLE}"
