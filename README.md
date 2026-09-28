# Gala Engine

Build unsigned iPhone and iPad IPAs on a Mac while working on Linux. Gala Engine syncs a project to the Mac's bulk volume, runs its `ios-build.sh` there, and copies the IPA and build log back. Tailscale supplies the private network; Gala Engine uses your existing SSH setup.

Gala Engine is deliberately small. A Mac-side worker owns the build volume and listens only on `127.0.0.1`; SSH carries its control calls and rsync traffic. There is no account, web UI, simulator, or GitHub push in the build path. It builds the files in your current working tree, including uncommitted edits.

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
cp /Volumes/BlenderBuild/gala-engine-tool/mac/com.gala.engine.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.gala.engine.plist
```

This Mac already has the worker running under the included [`mac/com.gala.engine.plist`](mac/com.gala.engine.plist), with its script at `/Volumes/BlenderBuild/gala-engine/service.py`. The LaunchAgent was verified to restart the worker after a process stop. For a fresh setup, install the plist in `~/Library/LaunchAgents/` and load it with `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.gala.engine.plist`. It starts when that user logs in after a reboot. The plist sends console output to `/dev/null` because launchd could not open a log file on this USB volume; each build still writes its own log there. If `gala doctor` reports a volume access error, grant `/opt/homebrew/bin/python3` access in System Settings → Privacy & Security → Full Disk Access. The worker keeps its script, configuration, source mirrors, and build caches on the USB volume. It binds rsync to `127.0.0.1:18730` and build control to `127.0.0.1:18731`; the client reaches both through SSH.

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
| `GALA_ARTIFACT_DIR` | Fresh directory for this run. Write one or more unsigned `.ipa` files here. |
| `GALA_JOBS` | Suggested parallel job count. Defaults to 2 for this Mac. |
| `GALA_PLATFORM` | `ios`. |

The script can call `xcodebuild`, CMake/Ninja, Expo prebuild, or other project tools. It must exit nonzero on failure and put an IPA in the artifact directory on success. Gala Engine checks the ZIP and `Payload/*.app` layout, calculates SHA-256, and returns the build log either way. `gala run` then signs and installs the IPA on the connected device.

Run the build from anywhere under the project:

```sh
gala build
```

Results arrive at `.gala/runs/<job-id>/` in the project. Add `.gala/` to the project's `.gitignore`.

The Mac mirror name includes a short hash of the Git remote and the project's path within that repo, so projects with the same directory name do not collide. Use `--name` to choose a fixed mirror name when needed.

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
gala run
```

`gala run` syncs, builds, returns the IPA, signs it with `zsign`, and installs it over USB with `ideviceinstaller`. Open the app on the device after installation. Linux's `idevicedebug` cannot launch this iOS 27 phone yet because it asks for a matching developer image. Use `gala build` and `gala deploy` separately when diagnosing a step; `deploy` accepts an IPA path. The device's first app launch may ask you to trust the developer. See the upstream [pairing](https://github.com/libimobiledevice/libimobiledevice/blob/master/docs/idevicepair.1), [Developer Mode](https://github.com/libimobiledevice/libimobiledevice/blob/master/docs/idevicedevmodectl.1), [install](https://github.com/libimobiledevice/ideviceinstaller/blob/master/README.md), and [signing](https://github.com/zhlynn/zsign) documentation for the underlying commands.

On this ThinkPad, the saved `iPhone USB hotspot` and `iPhone Wi-Fi hotspot` NetworkManager profiles have auto-connect disabled. USB pairing, signing, and installation still work while tethering is off. To use phone data over USB, run `nmcli connection up "iPhone USB hotspot"`; to stop, run `nmcli connection down "iPhone USB hotspot"`. The phone must have Personal Hotspot enabled for the connection to come up. NetworkManager will not reconnect these profiles automatically after a disconnect.

## Sync behavior

Normal `rsync` uses file size and modification time to decide which paths need inspection. For a changed file, it transfers differences rather than blindly copying the entire tree. A Git branch switch may update timestamps and cause some otherwise identical files to be sent again. Gala Engine has no cross-branch content store on the client or Mac. The rsync daemon runs on the Mac under the local worker's volume access; its port is available only through SSH.

Use `gala sync --dry-run` to see what would change. Use `gala build --checksum` when timestamp churn is causing excess transfer; that compares file contents on both machines, but reads the whole tree on both sides. The default is faster for ordinary edit-build cycles.

Gala Engine excludes Git metadata, `.gala`, Nix/Node/Expo/Xcode build directories, and patterns from each `.gitignore`. It deletes synced files removed from the client source mirror while preserving `GALA_BUILD_DIR` and past run artifacts. Large dependencies already installed on the Mac can live outside the mirror and be referenced by `ios-build.sh`.

## Existing projects

- **Native SwiftUI/UIKit:** Put `xcodebuild` in `ios-build.sh`, set a stable `-derivedDataPath` inside `GALA_BUILD_DIR`, target `generic/platform=iOS`, and package the device `.app` as `Payload/App.app` in the IPA. The project decides whether signing happens on the Mac or later on Linux.
- **Blender port:** Reuse the device CMake/Ninja and `package_sideload_ipa.py` commands from its current PR preview workflow. Keep the dependency prefix and revision-matched host tools on the Mac's bulk volume. Give Gala Engine's mirror a new CMake build directory because CMake caches the source path.
- **Expo:** Prebuild the iOS project on the Mac, then run its Xcode build in `ios-build.sh`. `eas build --local` is an alternative for EAS parity, but Expo's local mode does not support caching.

The Mac serializes build recipes across all Gala Engine projects, which fits its 8 GB of RAM. Source sync can happen before a build slot becomes free.

## SourceKit language service

This Mac has `sourcekit-lsp` in Xcode, but Gala Engine does not yet proxy it to Linux editors. A useful proxy needs to keep the project mirror current, start SourceKit from the Mac worker so it can read the USB volume, and translate `file://` document paths in both directions between the Linux checkout and Mac mirror. Running `ssh macbook xcrun sourcekit-lsp` alone would hit the USB volume access failure observed here. Build output and diagnostics are available today through `gala build` and its log.

## Agent use

The shared `~/.agents/skills/gala-engine/SKILL.md` gives agents the command sequence and output rules. Project-specific build logic belongs in each project's `ios-build.sh`; this repository's [AGENTS.md](AGENTS.md) covers changes to Gala Engine itself.
