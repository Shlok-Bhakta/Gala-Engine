---
title: Signing and profiles
description: How the Mac chooses a certificate and provisioning profile, advances build numbers, and what your profile needs.
---

Recipes produce **unsigned** IPAs. The Mac signs each delivery just before publishing it, so recipes never deal with certificates. This page covers what the Mac needs and how it decides.

## What the Mac needs

- **A provisioning profile** that lists your iPhone and iPad under `ProvisionedDevices`, installed in `~/Library/MobileDevice/Provisioning Profiles/` or Xcode’s `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`. Development and ad hoc profiles both work.
- **The matching certificate and its private key** in the login keychain. Check with:

  ```sh
  security find-identity -v -p codesigning
  ```

- **Keychain access for codesign.** On a fresh setup `codesign` can wait for a keychain prompt that nobody sees. Grant Apple’s signing tools access to the key once from a Mac shell. SSH works:

  ```sh
  security set-key-partition-list -S apple-tool:,apple: -s -t private \
    -l 'Apple Development: Your Name (TEAMID)' ~/Library/Keychains/login.keychain-db
  ```

  Enter the keychain password at the prompt. Never put it in a command argument or give it to an agent.

## How a profile is chosen

For each app, the worker looks at every installed profile and keeps those that:

1. have not expired,
2. list at least one device, and
3. include a certificate whose identity is in the keychain.

From those it picks the most specific match for the bundle ID. An explicit App ID such as `TEAMID.com.example.app` beats any wildcard. Among wildcards, the longest prefix wins. Entitlements come from the chosen profile, with `application-identifier` and keychain groups rewritten for the app. Nested frameworks, dylibs, and app extensions are signed first, and the app is verified with `codesign --verify --deep --strict` before publishing.

Before signing anything, the worker signs a throwaway file with a 15-second timeout. If the keychain is waiting for approval, you get `Mac keychain did not grant codesign access to the signing key within 15 seconds` instead of a hung build.

## Build numbers

The Mac sets `CFBundleVersion` on every delivery, including in app extensions, so iOS always treats a new build as an update. The new number is one more than the highest of:

- the last number this project delivered,
- the highest build of the same bundle ID currently published by any checkout, and
- the leading number in the recipe’s own `CFBundleVersion`.

`CFBundleShortVersionString` and `CFBundleIdentifier` are never changed.

:::caution[Keep the bundle ID stable]
iOS updates an installed app in place, keeping its data, only when the bundle ID and signing team match. Changing `CFBundleIdentifier` installs a second copy with an empty data container.
:::

## iPhone and iPad from one IPA

Set `UIDeviceFamily` to `[1, 2]` in your `Info.plist`, and one IPA installs on both. `gala deliver` warns when an app does not declare both families.

## Ad hoc vs. development

Both profile types install over the air on listed devices. Apple documents ad hoc distribution for wireless installs. Development-signed builds also install and update in practice, but check that updates keep your data on your devices before relying on it.

## Push notifications in your own apps

Gala signs with whatever entitlements your profile grants. If an app needs push, iCloud, or App Groups, use an explicit App ID with those capabilities and a profile generated after enabling them.
