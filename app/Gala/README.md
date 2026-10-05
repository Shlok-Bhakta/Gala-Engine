# Gala for iPhone and iPad

Gala is the native companion for a private Gala Engine build worker. It lists the current signed build for each project, starts the iOS installation handoff, and displays the IPA bytes the Mac has sent to iOS. It is written in SwiftUI for iOS and iPadOS 26 or later.

![Illustrated Gala screens](../../docs/assets/native-preview.svg)

The transfer bar measures the IPA response from the Mac. iOS does not provide this app with a final installation percentage or a callback when the installed app is ready. After the icon settles, close and reopen the updated app to see the new version. The current native build has been compiled and delivered through Gala, but its on-device installation and handoff still need verification.

## Install on the owner's devices

From a Linux checkout with Gala configured, run:

```sh
cd app/Gala
gala deliver
```

This tests, builds, signs, and publishes the current IPA through the Mac. Open the returned private Tailscale install URL in Safari on the iPhone and iPad to install Gala for the first time. Tailscale must be connected on the device. The owner's current provisioning profile includes only the registered devices; other users need their own signing profile.

After installation, Gala reads the Mac's Tailscale server address embedded at build time. You can change it with the gear button under **Settings → Mac**. The app shows the latest build for each project with its icon and refreshes while open; tapping **Install** requests a fresh one-time manifest, hands it to iOS, and follows the Mac's transfer status as a progress ring. After a finished transfer the button reads **Installed** for that build and **Update** when a newer one arrives. Long-press a build to open its web installer. If iOS rejects the direct handoff, Gala opens the existing private web installer.

## Build an unsigned IPA

Run the recipe on a Mac with the iPhoneOS SDK. Keep its work and artifact directories on a volume with enough space:

```sh
GALA_BUILD_DIR=/path/to/build-cache \
GALA_ARTIFACT_DIR=/path/to/artifacts \
GALA_DEFAULT_SERVER=none \
./ios-build.sh
```

`GALA_DEFAULT_SERVER=none` leaves the server field empty for a distributable unsigned build. With that variable omitted, the recipe embeds the Mac's Tailscale DNS name when available. An unsigned IPA needs to be signed with a profile that covers the target devices before installation.

## Notifications

In Settings, tap **Enable Build Alerts** to allow native notifications. Gala registers with APNs and sends its device token to the Mac over your tailnet. Development profiles use Apple's sandbox; production profiles use production APNs. The token is requested again on each launch and kept only in memory on the device. The Mac stores subscriptions on its external volume and sends an alert after each successful delivery. Tapping an alert opens Gala; choose Install to start installation.

The app requires a provisioning profile for `com.galaengine.app` with `aps-environment` and a matching signing certificate and private key in the Mac keychain. Delivery fails if only a wildcard profile is available. The Mac sender needs `apns.js`, `apns/apns-cert.pem`, and `apns/apns-key.pem` under the Gala storage root. See the root README for setup. The Home Screen web app continues to support Web Push independently.

Gala lists the current delivery for each app. Deliveries disappear after 48 hours, and a new delivery replaces the previous one. Starting another build or delivery for the same project also clears its previous delivery, even if the new run fails or never publishes; `gala test` and `gala exec` leave it installable. Cleanup removes the downloadable IPA and its listing, while installed apps and reusable build caches remain.
