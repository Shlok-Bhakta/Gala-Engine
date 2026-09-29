---
title: How Gala works
description: What happens on each machine when you run gala build or gala deliver, from sync to install.
---

Gala is one Python program, `bin/gala`. On your workstation it is the `gala` command. On the Mac the same file runs as a LaunchAgent in `mac-service` mode. Nothing else runs in the background.

## The delivery pipeline

When you run `gala deliver` in a project:

1. **Find the project.** Gala walks up from the current directory to the nearest folder that contains `ios-build.sh`. That folder is the project root.
2. **Pick a mirror.** The Mac keeps one source mirror per client checkout, named from the folder plus a short hash of the client hostname, checkout path, Git remote, and path within the repository, for example `swifttodo-1a2b3c4d`. Different machines and checkouts never overwrite each other. `--name` chooses a fixed mirror instead.
3. **Clean old results.** Gala deletes the previous run directories on both sides, so `.gala/runs/` only holds the current invocation.
4. **Sync.** rsync sends the working tree to the mirror, honoring every `.gitignore` and skipping `.git`, `.gala`, `node_modules`, `DerivedData`, `.build`, `build`, `.expo`, and `.direnv`. Uncommitted edits are included. Files you delete locally are deleted from the mirror, while `GALA_BUILD_DIR` is preserved.
5. **Test.** The worker runs `ios-test.sh` from the mirror. A failure stops here with a nonzero exit code and the log path.
6. **Build.** The worker waits for the Mac’s single build slot, runs `ios-build.sh`, and validates every IPA it wrote. The run directory with logs, reports, and IPAs is copied back to `.gala/runs/<job>/`.
7. **Sign and publish.** The worker picks a matching provisioning profile and keychain identity, advances `CFBundleVersion`, signs every nested framework and extension, verifies the signature, extracts the app icon, and replaces that project’s current OTA build.
8. **Notify.** Every device that subscribed to build alerts gets a push notification. Tapping it opens the install page.

`gala build` syncs and builds without the test step unless you pass `--gate`. `gala test` syncs and runs only `ios-test.sh`. `gala run` builds, then signs and installs over USB from Linux instead of publishing.

## What runs where

```text
Workstation                          Mac (LaunchAgent)                    iPhone / iPad
───────────                          ─────────────────                    ─────────────
gala deliver ──ssh──▶ 127.0.0.1:18731  control API (prepare, build, publish)
             ──ssh──▶ 127.0.0.1:18730  rsync daemon ◀── source mirror
                                     127.0.0.1:18732  install server
                                        ▲
                                        └── tailscale serve /gala ◀──────── Gala app, Safari
```

The Mac worker listens only on `127.0.0.1`. Clients reach the control API and rsync daemon through SSH, which runs `curl` and `nc` on the Mac. Tailscale Serve publishes the install server at `https://<mac-tailnet-name>/gala/`, inside your tailnet only. When the client is the Mac itself, Gala skips SSH and talks to localhost directly.

## One build slot

The Mac runs one recipe at a time across all projects and clients, using a lock on the build volume. Syncs are not serialized, so a client can upload while another build finishes. Each checkout also takes a local lock, so two Gala commands in the same checkout wait for each other.

## One current build per app

The Mac keeps no build history. Each project has one signed `current.ipa`, which is replaced atomically by the next delivery and expires after 48 hours. When several checkouts deliver the same bundle ID, the dashboard lists only the newest one, and build numbers keep increasing across all of them.

## Install tracking

iOS installs over-the-air builds through an `itms-services` link to a manifest. Gala gives each install attempt a token and tracks it on the Mac:

| Stage | Meaning |
| --- | --- |
| `ready` | The attempt exists; iOS has not asked for anything yet. |
| `manifest` | iOS fetched the manifest and is showing its install prompt. |
| `downloading` | iOS is downloading the IPA. `sent` and `total` report bytes sent by the Mac. |
| `transferred` | The Mac sent the whole IPA. iOS finishes installing on the device. |
| `interrupted` | The download connection dropped. |
| `superseded` | A newer build replaced this one before the install finished. |

iOS does not report the final install result back to Gala. A complete transfer means the Mac served the IPA. Check the app icon and version on the device after iOS finishes.
