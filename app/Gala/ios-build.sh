#!/usr/bin/env bash
set -euo pipefail

: "${GALA_BUILD_DIR:?Gala Engine sets this}"
: "${GALA_ARTIFACT_DIR:?Gala Engine sets this}"

sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
work="$(mktemp -d "${GALA_BUILD_DIR}/gala-app.XXXXXX")"
trap 'rm -rf "$work"' EXIT
app="$work/Payload/Gala.app"
mkdir -p "$app" "$GALA_ARTIFACT_DIR"
cp Info.plist "$app/Info.plist"

xcrun actool Assets.xcassets \
  --compile "$app" \
  --platform iphoneos \
  --minimum-deployment-target 26.0 \
  --target-device iphone \
  --target-device ipad \
  --app-icon AppIcon \
  --output-partial-info-plist "$work/icon-info.plist"

python3 - "$app/Info.plist" "$work/icon-info.plist" <<'PY'
import json
import os
import plistlib
import subprocess
import sys

info_path, icon_path = sys.argv[1:]
with open(info_path, "rb") as file:
    info = plistlib.load(file)
with open(icon_path, "rb") as file:
    info.update(plistlib.load(file))

server = os.environ.get("GALA_DEFAULT_SERVER", "")
if not server:
    try:
        result = subprocess.run(
            ["/opt/homebrew/bin/tailscale", "status", "--json"],
            capture_output=True, text=True, check=True,
        )
        hostname = json.loads(result.stdout)["Self"]["DNSName"].rstrip(".")
        server = f"https://{hostname}/gala"
    except (FileNotFoundError, KeyError, ValueError, subprocess.CalledProcessError):
        pass
if server:
    info["GalaDefaultServer"] = server
with open(info_path, "wb") as file:
    plistlib.dump(info, file)
PY

xcrun swiftc \
  -sdk "$sdk" \
  -target arm64-apple-ios26.0 \
  -parse-as-library \
  -module-name Gala \
  -O \
  -framework SwiftUI \
  -framework UIKit \
  Sources/*.swift \
  -o "$app/Gala"

(cd "$work" && zip -qry "$GALA_ARTIFACT_DIR/Gala-unsigned.ipa" Payload)
