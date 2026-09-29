---
title: The Gala app
description: Use the native iPhone and iPad companion or the web dashboard to open private installs.
---

Gala's native iPhone and iPad app lists the newest signed build for each project, with its extracted app icon. It can request an install and hand the manifest to iOS. The web dashboard provides the first install path and Home Screen build alerts. Both talk to the Mac's private Tailscale installer.

The native app targets iOS and iPadOS 26 or later. Its source is in [`app/Gala`](https://github.com/Shlok-Bhakta/Gala-Engine/tree/main/app/Gala). The current native build has been compiled and delivered through Gala; the direct on-device installation handoff still needs hands-on verification. Use the web installer if iOS rejects the native handoff.

## First install

From the Gala Engine checkout, run `gala deliver` in `app/Gala`. The recipe embeds the Mac's Tailscale DNS name when it is available. Open the printed private URL in Safari on a registered device to install Gala. If the address changes later, edit the server in the app's settings.

## What the progress ring means

The ring tracks the IPA response sent by the Mac to iOS. It does not prove that iOS finished installing the app. After the icon settles, open the installed app and check the build. Gala does not silently install apps.

## Build alerts

Native push alerts are not part of this release. Add the web dashboard to each device's Home Screen, then enable alerts there. Its Web Push subscription stays on the Mac's external volume. When a new delivery succeeds, tapping the alert opens that build's install page. See [iPhone and iPad setup](/setup/devices/).
