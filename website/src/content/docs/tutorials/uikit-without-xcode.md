---
title: UIKit without an Xcode project
description: Build the included UIKit example into an unsigned device IPA, then publish it to your tailnet.
---

The [UIKitHello example](https://github.com/Shlok-Bhakta/Gala-Engine/tree/main/examples/UIKitHello) uses `swiftc` and a small `ios-build.sh`. It makes a real iPhoneOS IPA without an `.xcodeproj`.

## Build the example

From a Gala Engine checkout on a configured client:

```sh
cd examples/UIKitHello
gala doctor
gala build
```

Gala syncs `App.swift`, `Info.plist`, and `ios-build.sh` to its Mac mirror. The recipe compiles for `arm64-apple-ios18.0`, places the app in `Payload/GalaHello.app`, and writes `GalaHello-unsigned.ipa` under `GALA_ARTIFACT_DIR`. The CLI returns the IPA and `build.log` in `.gala/runs/<job-id>/`.

## Publish to a registered device

This example has no `ios-test.sh`, so `gala deliver` will stop at the required test gate. After inspecting the build log, publish the existing unsigned IPA instead:

```sh
gala publish
```

The Mac signs the IPA with a matching profile, checks the private HTTPS URL, and prints the install page. Open that URL in Safari on a registered iPhone or iPad with Tailscale connected. Confirm the iOS install prompt and open the app after its icon settles.

For a tested delivery loop, add a meaningful executable `ios-test.sh` to the project, then use `gala deliver`. See [Tests and delivery](/guides/delivery/).
