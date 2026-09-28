#!/usr/bin/env bash
set -euo pipefail

sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
plutil -lint Info.plist
xcrun swiftc -typecheck -sdk "$sdk" -target arm64-apple-ios26.0 \
  -parse-as-library -module-name Gala -framework SwiftUI -framework UIKit Sources/*.swift
python3 - <<'PY'
import plistlib
with open("Info.plist", "rb") as file:
    info = plistlib.load(file)
assert info["CFBundleIdentifier"] == "com.galaengine.app"
assert info["UIDeviceFamily"] == [1, 2]
print("Gala native app typecheck and bundle identity passed")
PY
