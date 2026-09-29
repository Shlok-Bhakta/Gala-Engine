---
title: USB install from Linux
description: Pair an iPhone or iPad with a Linux client, then build, sign, and install through Gala.
---

USB installs require the ThinkPad setup described in the [repository README](https://github.com/Shlok-Bhakta/Gala-Engine#pair-and-deploy-from-the-thinkpad): `usbmuxd`, device tools, `zsign`, and local signing files. A remote host without those pieces can still use private [OTA delivery](/guides/delivery/).

## Pair the device

Connect and unlock the iPhone or iPad, then enter the Gala Engine Nix shell:

```sh
nix develop ~/Projects/Gala-Engine
gala device list
gala device pair
gala device doctor
```

Accept **Trust This Computer** on the device. Enable Developer Mode under Settings → Privacy & Security if `gala device doctor` calls for it. With multiple devices connected, pass `--udid <device-id>`.

## Set up local signing

Keep a `.p12` with the certificate and private key and a matching `.mobileprovision` outside Git. Gala's defaults are `~/.config/gala-engine/development.p12` and `development.mobileprovision`. It reads the P12 password from `development.p12.password` when present, or prompts in an interactive shell. The profile must include the target device and app bundle ID.

## Install an app

From a project with `ios-build.sh`:

```sh
gala run
```

`gala run --gate` runs `ios-test.sh` first. Gala builds on the Mac, returns the unsigned IPA, signs it on Linux, then asks `ideviceinstaller` to upgrade the installed app. On a first install it falls back to install. Keep the bundle ID stable so iOS updates the same app and retains its data.

To separate build and device steps while debugging, run `gala build`, then `gala deploy path/to/unsigned.ipa`. Open the app on the device to verify its screen and behavior.
