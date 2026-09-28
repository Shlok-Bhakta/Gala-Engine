#!/usr/bin/env bash
set -euo pipefail

: "${GALA_BUILD_DIR:?Gala Engine sets this}"
: "${GALA_ARTIFACT_DIR:?Gala Engine sets this}"

sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
work="$(mktemp -d "${GALA_BUILD_DIR}/todo.XXXXXX")"
trap 'rm -rf "$work"' EXIT
app="$work/Payload/SwiftTodo.app"
mkdir -p "$app" "$GALA_ARTIFACT_DIR"
cp Info.plist "$app/Info.plist"

xcrun swiftc \
  -sdk "$sdk" \
  -target arm64-apple-ios18.0 \
  -parse-as-library \
  -module-name SwiftTodo \
  -O \
  -framework SwiftUI \
  App.swift \
  -o "$app/SwiftTodo"

(cd "$work" && zip -qry "$GALA_ARTIFACT_DIR/SwiftTodo-unsigned.ipa" Payload)
