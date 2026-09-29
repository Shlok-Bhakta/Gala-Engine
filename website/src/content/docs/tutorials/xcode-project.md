---
title: An existing Xcode project
description: Add a Gala recipe to an Xcode app without changing its project structure.
---

Gala does not inspect an Xcode project. Add `ios-build.sh` beside the `.xcodeproj` or `.xcworkspace` and make the recipe produce an unsigned iPhoneOS IPA. Replace the project, scheme, and app names below with yours.

```bash title="ios-build.sh"
#!/usr/bin/env bash
set -euo pipefail

xcodebuild -project MyApp.xcodeproj -scheme MyApp \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$GALA_BUILD_DIR/DerivedData" \
  CODE_SIGNING_ALLOWED=NO build

app="$GALA_BUILD_DIR/DerivedData/Build/Products/Release-iphoneos/MyApp.app"
test -d "$app"
package="$GALA_BUILD_DIR/package"
mkdir -p "$package/Payload" "$GALA_ARTIFACT_DIR"
cp -R "$app" "$package/Payload/"
(cd "$package" && zip -qry "$GALA_ARTIFACT_DIR/MyApp-unsigned.ipa" Payload)
```

Make it executable, then build from the project:

```sh
chmod +x ios-build.sh
gala build
```

For a workspace, replace `-project MyApp.xcodeproj` with `-workspace MyApp.xcworkspace`. Xcode must build for `generic/platform=iOS`; a simulator `.app` cannot be packaged as a device IPA. Keep DerivedData in `GALA_BUILD_DIR` so the next build can reuse it.

Add an executable `ios-test.sh` that runs your project's real checks before using `gala deliver`. If you already have an unsigned IPA and want a one-time install, use `gala publish path/to/ipa` from this project. The Mac signing profile must cover the app bundle ID and device. See [Signing and profiles](/setup/signing/).
