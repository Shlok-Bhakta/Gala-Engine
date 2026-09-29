---
title: CLI reference
description: Gala commands for readiness, sync, tests, builds, private delivery, and USB installs.
---

Run `gala` from a project directory or any of its subdirectories. Gala locates the nearest `ios-build.sh`. Bare `gala` is `gala run`, which needs a configured Linux USB device.

| Command | Result |
| --- | --- |
| `gala doctor` | Check the Mac's Xcode SDK, worker storage, rsync service, and private installer. |
| `gala sync --dry-run` | Show source changes without copying or building. |
| `gala test` | Run `ios-test.sh` on the Mac and return its log and reports. |
| `gala build` | Build and return an unsigned IPA and log. |
| `gala build --gate` | Require tests before building. |
| `gala deliver` | Require tests, build, Mac sign, and publish the current private IPA. |
| `gala build --deliver` | The same gated delivery path from the build command. |
| `gala publish [ipa]` | Mac sign and publish an existing unsigned IPA from a Gala project. With no path, use the latest Gala build. |
| `gala run` | Build, sign on a configured Linux client, and install over USB. |
| `gala deploy [ipa]` | Sign and USB install an existing unsigned IPA. |
| `gala device list`, `pair`, `doctor` | Inspect and prepare a USB iPhone or iPad on Linux. |
| `gala watch --action deliver` | Repeat tested delivery after edits. |

`gala watch` defaults to the USB `run` action. Choose `--action build` for unsigned builds or `--action test` for test-only loops.

## Common options

`--host` selects the Mac SSH alias. `--root` selects the Mac storage root and must match the service. Source commands accept `--checksum` to compare file contents during sync and `--dry-run` to preview sync changes. `--name` chooses a fixed mirror name; avoid sharing one name across active checkouts.

`--gate` applies to `build` and `run`. `--udid` selects a USB device when more than one is connected. `--p12` and `--profile` override Linux USB signing files.

See [`gala --help`](https://github.com/Shlok-Bhakta/Gala-Engine/blob/main/bin/gala) and each subcommand's `--help` for the complete current flags.
