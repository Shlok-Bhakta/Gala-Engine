---
title: FAQ
description: Short answers about supported projects, devices, testing, and build storage.
---

## Can I use Gala without a Mac?

No. Apple device builds and Mac OTA signing use Xcode and its iPhoneOS SDK on a Mac. The current published client workflow runs from Linux over SSH.

## Does my app need an Xcode project?

No. It needs an executable `ios-build.sh` that writes a valid unsigned device IPA. The [UIKit example](/tutorials/uikit-without-xcode/) uses `swiftc` directly.

## Can I install the IPA from `gala build`?

Not until it is signed. Use `gala deliver` for a tested private OTA build, `gala publish` for an existing unsigned IPA, or `gala run` on a configured Linux USB client.

## Does Gala test my app's screen?

Only if your `ios-test.sh` actually runs such a test. `gala test` reports the script's result; this setup does not drive a physical device UI. Check screen and touch behavior on an installed build.

## Can another person install my build?

Only if their device can reach your tailnet installer and is listed in the signing profile. Gala is designed for a private set of registered devices, not public distribution or App Store releases.

## Where did my previous IPA go?

Gala keeps the current signed IPA per project for 48 hours. Each new command removes prior `.gala/runs/` directories. Copy logs or artifacts you want to retain before the next run.
