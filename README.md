# Gala Engine

Build iPhone and iPad IPAs on a Mac while working on Linux. Gala Engine syncs a project to the Mac's bulk volume, runs its `ios-build.sh` there, and copies the unsigned IPA and build log back. For delivery, the Mac signs the IPA and hosts the current build privately over Tailscale. A Home Screen web app can notify an iPhone and iPad when the update is ready.

The Mac-side worker owns the build volume and listens only on `127.0.0.1`; SSH carries its control calls and rsync traffic. Tailscale Serve exposes the install page, manifest, and signed IPA only to the tailnet. There is no account, simulator, or GitHub push in the build path. Gala builds the files in your current working tree, including uncommitted edits.

## One-time setup

On the Mac, install Xcode and its iPhoneOS SDK. Keep the bulk build volume mounted. On the client, make sure `ssh macbook` reaches the Mac over Tailscale. If your SSH alias has another name, use `GALA_HOST` or `--host`.

For a fresh client, add an SSH alias using the Mac's Tailscale name from `tailscale status`:

```sshconfig
Host macbook
    HostName <mac-tailnet-name>
    User <mac-user>
```

On the Mac, turn on System Settings → General → Sharing → Remote Login, with access for that user. The Mac worker needs local access to the external volume. This Mac's SSH sessions receive `Interrupted system call` on the USB volume despite Remote Login's full disk access option, so Gala Engine never writes project files there through an SSH shell. Install the worker from a local Mac session:

```sh
mkdir -p /Volumes/BlenderBuild/gala-engine
git clone git@github.com:Shlok-Bhakta/Gala-Engine.git /Volumes/BlenderBuild/gala-engine-tool
cp /Volumes/BlenderBuild/gala-engine-tool/bin/gala /Volumes/BlenderBuild/gala-engine/service.py
cp /Volumes/BlenderBuild/gala-engine-tool/mac/{dashboard.html,sw.js,manifest.webmanifest,icon.svg,icon-57.png,icon-512.png,webpush.js,package.json,package-lock.json} /Volumes/BlenderBuild/gala-engine/
cd /Volumes/BlenderBuild/gala-engine
npm_config_cache=/Volumes/BlenderBuild/gala-engine/npm-cache npm ci --ignore-scripts --no-audit --no-fund
cp /Volumes/BlenderBuild/gala-engine-tool/mac/com.gala.engine.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.gala.engine.plist
tailscale serve --bg --https=443 --set-path=/gala http://127.0.0.1:18732
```

The LaunchAgent starts when that user logs in after a reboot. The plist sends console output to `/dev/null` because launchd could not open a log file on this USB volume; each build still writes its own log there. If `gala doctor` reports a volume access error, grant `/opt/homebrew/bin/python3` access in System Settings → Privacy & Security → Full Disk Access. The worker keeps its script, configuration, source mirrors, build caches, signed current IPAs, and push subscriptions on the USB volume. It binds rsync to `127.0.0.1:18730`, build control to `127.0.0.1:18731`, and the private install server to `127.0.0.1:18732`. Keep the Tailscale Serve route tailnet only. Do not use Funnel for `/gala`.

For Mac signing, install a valid development or ad hoc profile that includes both devices and a matching certificate with its private key in the Mac keychain. The current wildcard development profile lists two devices and the matching certificate. On this Mac, `codesign` currently waits for keychain authorization. You can grant Apple signing tools access to this specific development key from an interactive Mac shell, including an SSH shell, without opening the laptop:

```sh
security set-key-partition-list -S apple-tool:,apple: -s -t private -l 'Apple Development: ZIYANG CHEN (ZIYANG CHEN)' ~/Library/Keychains/login.keychain-db
```

Enter the Mac login keychain password at its prompt. Do not put it in a shell argument or send it to an agent. Until that authorization succeeds, `gala deliver` cannot produce an installable OTA IPA.

Clone Gala Engine on the client and enter its Nix shell:

```sh
git clone git@github.com:Shlok-Bhakta/Gala-Engine.git ~/Projects/Gala-Engine
nix develop ~/Projects/Gala-Engine
gala doctor
```

You can also add the command to an existing shell without entering a development shell:

```sh
nix shell ~/Projects/Gala-Engine#default
```

`gala doctor` checks Xcode, the iPhoneOS SDK, and whether the Mac worker can write to the selected build root. The default Mac storage root is `/Volumes/BlenderBuild/gala-engine`. Override it with `GALA_REMOTE_ROOT` if this Mac uses another bulk volume; start the worker with the matching `--root`. Gala Engine creates its own project mirrors under that root; it never syncs into your normal Mac checkout or the Mac's internal disk.

## Add a project

Put one file named `ios-build.sh` at the root of the project. It runs on the Mac with these variables:

| Variable | Meaning |
| --- | --- |
| `GALA_BUILD_DIR` | Persistent directory for Xcode DerivedData, CMake/Ninja output, and other incremental build data. |
| `GALA_ARTIFACT_DIR` | Fresh directory for this run. Builds write unsigned `.ipa` files here; tests may write reports here. |
| `GALA_JOBS` | Suggested parallel job count. Defaults to 2 for this Mac. |
| `GALA_PLATFORM` | `ios`. |

Gala Engine does not detect whether a project uses CMake, Xcode, React Native, or Expo. It runs `ios-build.sh` from the mirrored project root on the Mac. The script decides every build command. Put its final unsigned IPA anywhere under `GALA_ARTIFACT_DIR`; the worker finds IPAs recursively, validates them, and sends them back with a build log and manifest. If another tool writes the IPA elsewhere, copy it into that directory in the recipe. There is no separate output-path setting.

The script can call `xcodebuild`, CMake/Ninja, Expo prebuild, or other project tools. It must exit nonzero on failure and put an IPA in the artifact directory on success. Gala Engine checks the ZIP and `Payload/*.app` layout, calculates SHA-256, and returns the build log either way. Bare `gala` builds, signs, and deploys to the connected device. `gala run` does the same thing.

To get `gala` from an app's own `nix develop`, add Gala Engine to that app's flake dev shell. The [SwiftTodo flake](examples/SwiftTodo/flake.nix) is a minimal example. From its directory, the daily flow is:

```sh
nix develop
gala
```

Run the build from anywhere under the project:

```sh
gala build
```

Results arrive at `.gala/runs/<job-id>/` in the project. Add `.gala/` to the project's `.gitignore`. Before a new test, build, run, or delivery, Gala deletes the prior run directories from both the Linux checkout and its Mac mirror. A gated invocation keeps its test and build results together until the next invocation. The Mac keeps `GALA_BUILD_DIR` and the current source mirror for incremental builds; it does not keep a history of IPAs.

The Mac mirror name includes a short hash of the client hostname, checkout path, Git remote, and the project's path within that repo. Different Linux hosts and checkouts cannot overwrite each other's synced source. A lock also serializes Gala runs from the same checkout. Use `--name` only when deliberately reusing a fixed mirror; sharing a name across active clients can cause a sync collision.

## Test, gate, and publish

For Mac-side tests, add an executable `ios-test.sh` at the same root as `ios-build.sh`. It can run Swift or XCTest unit tests, JavaScript tests, linting, static checks, or custom project commands. It receives the same `GALA_*` variables as the build recipe. Write JUnit XML, coverage, and other reports under `GALA_ARTIFACT_DIR` to retrieve them. It does not need to produce an IPA.

```sh
gala test              # sync, run ios-test.sh, return test.log and reports
gala build --gate      # test must pass before building
gala run --gate        # ThinkPad: test, build, sign, and upgrade over USB
gala deliver           # test, build, Mac sign, publish the current OTA build
gala build --deliver   # same delivery flow from the build command
gala watch             # ThinkPad: run once, then rebuild and upgrade after edits
gala watch --action deliver  # test, build, sign, and notify after edits
```

`gala deliver` is the one-command agent path on crabcake. It requires `ios-test.sh`; a missing or failing test prevents signing and notification. `gala build --deliver` does the same. A recipe failure returns a nonzero CLI status and the log path. Agents should read the full log, fix the cause, and retry. A successful test step only proves what that project's test script actually checks. The SwiftTodo example currently checks iOS Swift type correctness and bundle identity; the owner separately confirmed its task UI on a physical phone.

`gala watch` polls tracked and non-ignored untracked source files, waits for edits to settle, then repeats the selected action. It keeps watching after a failed action. It ignores `.gala`, Git metadata, and common generated build directories. Use `--action build` for an unsigned artifact without a phone, or `--action deliver` to publish each successful gated build. `--gate` works with watch's `build` and `run` actions. Stop it with Ctrl-C. Watch is a plain terminal loop, not a multi-pane TUI.

`gala publish [path/to/unsigned.ipa]` sends an existing IPA to the Mac to sign and serve, without rebuilding. By default it selects the latest unsigned Gala IPA in the project. It prints the private HTTPS install page and signed IPA URL, and writes `.gala/current-publish.json`. The Mac advances `CFBundleVersion` for each delivery, while keeping `CFBundleIdentifier` stable. The current signed IPA replaces the prior one for that project and expires after 48 hours. No IPA is uploaded to Planista or GitHub. The Mac needs a profile that covers the app bundle ID and both devices. A single universal IPA can update both devices when its `UIDeviceFamily` includes iPhone and iPad.

On each iPhone and iPad, connect Tailscale, open `https://<mac-tailnet-name>/gala/` in Safari, use **Add to Home Screen**, open Gala from the Home Screen, and tap **Enable build notifications**. Gala stores one Web Push subscription per device on the Mac's external drive. When a delivery succeeds, the Mac sends both devices a notification. Tapping it opens the private install page and attempts the `itms-services` handoff. If iOS blocks the automatic handoff, tap **Install update** on that page. This uses Apple's device-signed OTA installation path; it needs no MDM or erase. The device may still display its own install confirmation. The signed app must keep the same bundle ID to update the existing icon and data.

Gala does not run physical iOS UI automation from crabcake. Maestro's iOS flows require an Apple simulator, which this setup intentionally does not use. A pass on `gala test` and `gala build` therefore cannot claim that the app's actual screen or touch flow was verified. The current device check is a human opening the OTA build or using `gala run` from the ThinkPad and reporting behavior. Device UI automation needs a future physical-device runner with an attached iPhone or iPad.

For a real minimal UIKit example:

```sh
cd ~/Projects/Gala-Engine/examples/UIKitHello
gala build
```

The example produces an unsigned arm64 iPhone/iPad IPA without an Xcode project or simulator.

## Pair and deploy from the ThinkPad

The Nix shell provides `idevicepair`, `idevicedevmodectl`, `ideviceinstaller`, `zsign`, and `lsusb`. NixOS must also run `usbmuxd`; the ThinkPad's `~/nixos-config` has device-specific USB rules for the owner's iPad and iPhone. Apply that system configuration with `nrs` before pairing. No simulator is involved.

Connect and unlock the device, then run:

```sh
nix develop ~/Projects/Gala-Engine
gala device list
gala device pair
gala device doctor
```

Accept **Trust This Computer** on the device and enter its passcode when prompted. If more than one Apple device is connected, pass `--udid` to the device commands. If Developer Mode is off, enable it on the device under Settings → Privacy & Security → Developer Mode; `idevicedevmodectl reveal` can make that menu visible. A passcode-protected device needs the final Developer Mode approval on its screen.

To sign on Linux, obtain a `.p12` containing the Apple Development certificate **and its private key**, plus a matching development `.mobileprovision` that includes the device and app bundle ID. Keep the private key outside Git. Gala Engine looks for `~/.config/gala-engine/development.p12` and `development.mobileprovision` by default. It reads `development.p12.password` from the same directory when present, or prompts for the password. Then, from the app project:

```sh
gala
```

`gala` syncs, builds, returns the IPA, signs it with `zsign`, and uses `ideviceinstaller upgrade` to update the app over USB. On a first install, it falls back to `ideviceinstaller install`. Keep the app's `CFBundleIdentifier` stable: changing it creates a separate icon and app data container. Open the app on the device after deployment. Linux's `idevicedebug` cannot launch this iOS 27 phone yet because it asks for a matching developer image. Use `gala build` and `gala deploy` separately when diagnosing a step; `deploy` accepts an IPA path. The device's first app launch may ask you to trust the developer. See the upstream [pairing](https://github.com/libimobiledevice/libimobiledevice/blob/master/docs/idevicepair.1), [Developer Mode](https://github.com/libimobiledevice/libimobiledevice/blob/master/docs/idevicedevmodectl.1), [install and upgrade](https://github.com/libimobiledevice/ideviceinstaller/blob/master/man/ideviceinstaller.1), and [signing](https://github.com/zhlynn/zsign) documentation for the underlying commands.

## Sync behavior

Normal `rsync` uses file size and modification time to decide which paths need inspection. For a changed file, it transfers differences rather than blindly copying the entire tree. A Git branch switch may update timestamps and cause some otherwise identical files to be sent again. Gala Engine has no cross-branch content store on the client or Mac. The rsync daemon runs on the Mac under the local worker's volume access; its port is available only through SSH.

Use `gala sync --dry-run` to see what would change. Use `gala build --checksum` when timestamp churn is causing excess transfer; that compares file contents on both machines, but reads the whole tree on both sides. The default is faster for ordinary edit-build cycles.

Gala Engine excludes Git metadata, `.gala`, Nix/Node/Expo/Xcode build directories, and patterns from each `.gitignore`. It deletes synced files removed from the client source mirror while preserving `GALA_BUILD_DIR`. Large dependencies already installed on the Mac can live outside the mirror and be referenced by `ios-build.sh`.

## Existing projects

- **Native SwiftUI/UIKit:** Put `xcodebuild` in `ios-build.sh`, set a stable `-derivedDataPath` inside `GALA_BUILD_DIR`, target `generic/platform=iOS`, and package the unsigned device `.app` as `Payload/App.app` in the IPA. `gala` signs the returned IPA on Linux.
- **Blender port:** Reuse the device CMake/Ninja and `package_sideload_ipa.py` commands from its current PR preview workflow. Keep the dependency prefix and revision-matched host tools on the Mac's bulk volume. Give Gala Engine's mirror a new CMake build directory because CMake caches the source path.
- **React Native:** Run its iOS release build through the generated Xcode workspace. The recipe handles JavaScript bundling, CocoaPods, the device `.app`, and IPA packaging. Keep DerivedData in `GALA_BUILD_DIR` and dependency caches on the Mac's bulk volume.
- **Expo:** Prebuild the iOS project on the Mac, then run its Xcode build in `ios-build.sh`. `eas build --local` is an alternative for EAS parity, but Expo's local mode does not support caching.

The Mac serializes build recipes across all Gala Engine projects, which fits its 8 GB of RAM. Source sync can happen before a build slot becomes free.

## SourceKit language service

This Mac has `sourcekit-lsp` in Xcode, but Gala Engine does not yet proxy it to Linux editors. A useful proxy needs to keep the project mirror current, start SourceKit from the Mac worker so it can read the USB volume, and translate `file://` document paths in both directions between the Linux checkout and Mac mirror. Running `ssh macbook xcrun sourcekit-lsp` alone would hit the USB volume access failure observed here. Build output and diagnostics are available today through `gala build` and its log.

## Agent use

The shared `~/.agents/skills/gala-engine/SKILL.md` gives agents the command sequence and output rules. Project-specific build logic belongs in each project's `ios-build.sh`; this repository's [AGENTS.md](AGENTS.md) covers changes to Gala Engine itself.
