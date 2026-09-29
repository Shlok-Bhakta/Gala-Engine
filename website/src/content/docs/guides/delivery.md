---
title: Delivery and installs
description: Choose a tested delivery, publish an existing IPA, and understand what devices report back.
---

`gala deliver` is the normal private preview path. It syncs your project, requires `ios-test.sh` to pass, builds an unsigned IPA, signs it on the Mac, and publishes the current signed build to the tailnet-only installer.

```sh
gala deliver
```

If you already built an unsigned IPA in a Gala project, `gala publish path/to/app.ipa` signs and publishes it without rebuilding or running tests. `gala build --deliver` follows the same gated path as `gala deliver`.

## Before publishing

The Mac needs a provisioning profile that covers the app bundle ID and each target iPhone or iPad, plus the matching signing certificate and private key. The app must be a device build. `gala build` alone returns an unsigned IPA that cannot be installed until it is signed. See [Signing and profiles](/setup/signing/).

## Install on a device

Connect Tailscale on the iPhone or iPad, open the install URL returned by Gala in Safari, and tap **Install update**. Confirm the iOS prompt. The private dashboard at `https://<mac-tailnet-name>/gala/` also lists current builds. You can add it to the Home Screen and enable build alerts on each device. The native Gala app can open the same installer.

Gala measures the bytes the Mac sends while iOS downloads the IPA. It cannot see the final iOS installation result. Once the icon settles, close and reopen the app, then check its version and behavior on the device. Keep the bundle ID and signing team stable for data-preserving updates; verify that update behavior with your actual profile.

## Lifetime and notifications

Each project has one current signed IPA. A new delivery replaces it, and it expires after 48 hours. Successful delivery attempts to notify subscribed devices through Web Push; the CLI prints the number sent and registered. An alert opens the installer, but iOS still needs a user action to install. A failed signing step or HTTPS check makes the command fail, so do not share an install URL from a failed delivery.
