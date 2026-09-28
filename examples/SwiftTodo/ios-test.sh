#!/usr/bin/env bash
set -euo pipefail

sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
plutil -lint Info.plist
xcrun swiftc -typecheck -sdk "$sdk" -target arm64-apple-ios18.0 \
  -parse-as-library -module-name SwiftTodo -framework SwiftUI App.swift
python3 - <<'PY'
import plistlib
with open('Info.plist', 'rb') as file:
    info = plistlib.load(file)
assert info['CFBundleIdentifier'] == 'com.galaengine.todo'
print('SwiftTodo iOS typecheck and bundle identity passed')
PY
