#!/usr/bin/env bash
set -euo pipefail

: "${PIPFORGE_BUILD_DIR:?Pipforge sets this}"
: "${PIPFORGE_ARTIFACT_DIR:?Pipforge sets this}"

sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
work="$(mktemp -d "${PIPFORGE_BUILD_DIR}/hello.XXXXXX")"
trap 'rm -rf "$work"' EXIT
app="$work/Payload/PipforgeHello.app"
mkdir -p "$app" "$PIPFORGE_ARTIFACT_DIR"
cp Info.plist "$app/Info.plist"

xcrun swiftc \
  -sdk "$sdk" \
  -target arm64-apple-ios18.0 \
  -parse-as-library \
  -module-name PipforgeHello \
  -O \
  App.swift \
  -o "$app/PipforgeHello"

(cd "$work" && zip -qry "$PIPFORGE_ARTIFACT_DIR/PipforgeHello-unsigned.ipa" Payload)
