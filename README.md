# Pipforge

Build unsigned iPhone and iPad IPAs on a Mac while working on Linux. Pipforge syncs a project to the Mac's bulk volume, runs its `ios-build.sh` there, and copies the IPA and build log back. Tailscale supplies the private network; Pipforge uses your existing SSH setup.

Pipforge is deliberately small. A Mac-side worker owns the build volume and listens only on `127.0.0.1`; SSH carries its control calls and rsync traffic. There is no account, web UI, simulator, or GitHub push in the build path. It builds the files in your current working tree, including uncommitted edits.

## One-time setup

On the Mac, install Xcode and its iPhoneOS SDK. Keep the bulk build volume mounted. On the client, make sure `ssh macbook` reaches the Mac over Tailscale. If your SSH alias has another name, use `PIPFORGE_HOST` or `--host`.

For a fresh client, add an SSH alias using the Mac's Tailscale name from `tailscale status`:

```sshconfig
Host macbook
    HostName <mac-tailnet-name>
    User <mac-user>
```

On the Mac, turn on System Settings → General → Sharing → Remote Login, with access for that user. The Mac worker needs local access to the external volume. This Mac's SSH sessions receive `Interrupted system call` on the USB volume despite Remote Login's full disk access option, so Pipforge never writes project files there through an SSH shell. Start the worker once from a local Mac session:

```sh
mkdir -p /Volumes/BlenderBuild/pipforge
git clone git@github.com:Shlok-Bhakta/Pipforge.git /Volumes/BlenderBuild/pipforge-tool
nohup python3 /Volumes/BlenderBuild/pipforge-tool/bin/pipforge mac-service \
  >>/Volumes/BlenderBuild/pipforge/service.log 2>&1 </dev/null &
```

This Mac already has the worker running under the included [`mac/com.pipforge.service.plist`](mac/com.pipforge.service.plist), with its script at `/Volumes/BlenderBuild/pipforge/service.py`. The LaunchAgent was verified to restart the worker after a process stop. For a fresh setup, install the plist in `~/Library/LaunchAgents/` and load it with `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.pipforge.service.plist`. It starts when that user logs in after a reboot. The plist sends console output to `/dev/null` because launchd could not open a log file on this USB volume; each build still writes its own log there. If `pipforge doctor` reports a volume access error, grant `/opt/homebrew/bin/python3` access in System Settings → Privacy & Security → Full Disk Access. The worker keeps its script, configuration, source mirrors, and build caches on the USB volume. It binds rsync to `127.0.0.1:18730` and build control to `127.0.0.1:18731`; the client reaches both through SSH.

Clone Pipforge on the client and enter its Nix shell:

```sh
git clone git@github.com:Shlok-Bhakta/Pipforge.git ~/Projects/Pipforge
nix develop ~/Projects/Pipforge
pipforge doctor
```

You can also add the command to an existing shell without entering a development shell:

```sh
nix shell ~/Projects/Pipforge#default
```

`pipforge doctor` checks Xcode, the iPhoneOS SDK, and whether the Mac worker can write to the selected build root. The default Mac storage root is `/Volumes/BlenderBuild/pipforge`. Override it with `PIPFORGE_REMOTE_ROOT` if this Mac uses another bulk volume; start the worker with the matching `--root`. Pipforge creates its own project mirrors under that root; it never syncs into your normal Mac checkout or the Mac's internal disk.

## Add a project

Put one file named `ios-build.sh` at the root of the project. It runs on the Mac with these variables:

| Variable | Meaning |
| --- | --- |
| `PIPFORGE_BUILD_DIR` | Persistent directory for Xcode DerivedData, CMake/Ninja output, and other incremental build data. |
| `PIPFORGE_ARTIFACT_DIR` | Fresh directory for this run. Write one or more unsigned `.ipa` files here. |
| `PIPFORGE_JOBS` | Suggested parallel job count. Defaults to 2 for this Mac. |
| `PIPFORGE_PLATFORM` | `ios`. |

The script can call `xcodebuild`, CMake/Ninja, Expo prebuild, or other project tools. It must exit nonzero on failure and put an IPA in the artifact directory on success. Pipforge checks the ZIP and `Payload/*.app` layout, calculates SHA-256, and returns the build log either way. Signing and loading onto a device remain separate steps.

Run the build from anywhere under the project:

```sh
pipforge build
```

Results arrive at `.pipforge/runs/<job-id>/` in the project. Add `.pipforge/` to the project's `.gitignore`.

The Mac mirror name includes a short hash of the Git remote and the project's path within that repo, so projects with the same directory name do not collide. Use `--name` to choose a fixed mirror name when needed.

For a real minimal UIKit example:

```sh
cd ~/Projects/Pipforge/examples/UIKitHello
pipforge build
```

The example produces an unsigned arm64 iPhone/iPad IPA without an Xcode project or simulator.

## Sync behavior

Normal `rsync` uses file size and modification time to decide which paths need inspection. For a changed file, it transfers differences rather than blindly copying the entire tree. A Git branch switch may update timestamps and cause some otherwise identical files to be sent again. Pipforge has no cross-branch content store on the client or Mac. The rsync daemon runs on the Mac under the local worker's volume access; its port is available only through SSH.

Use `pipforge sync --dry-run` to see what would change. Use `pipforge build --checksum` when timestamp churn is causing excess transfer; that compares file contents on both machines, but reads the whole tree on both sides. The default is faster for ordinary edit-build cycles.

Pipforge excludes Git metadata, `.pipforge`, Nix/Node/Expo/Xcode build directories, and patterns from each `.gitignore`. It deletes synced files removed from the client source mirror while preserving `PIPFORGE_BUILD_DIR` and past run artifacts. Large dependencies already installed on the Mac can live outside the mirror and be referenced by `ios-build.sh`.

## Existing projects

- **Native SwiftUI/UIKit:** Put `xcodebuild` in `ios-build.sh`, set a stable `-derivedDataPath` inside `PIPFORGE_BUILD_DIR`, target `generic/platform=iOS`, and package the device `.app` as `Payload/App.app` in the IPA. The project decides whether signing happens on the Mac or later on Linux.
- **Blender port:** Reuse the device CMake/Ninja and `package_sideload_ipa.py` commands from its current PR preview workflow. Keep the dependency prefix and revision-matched host tools on the Mac's bulk volume. Give Pipforge's mirror a new CMake build directory because CMake caches the source path.
- **Expo:** Prebuild the iOS project on the Mac, then run its Xcode build in `ios-build.sh`. `eas build --local` is an alternative for EAS parity, but Expo's local mode does not support caching.

The Mac serializes build recipes across all Pipforge projects, which fits its 8 GB of RAM. Source sync can happen before a build slot becomes free.

## SourceKit language service

This Mac has `sourcekit-lsp` in Xcode, but Pipforge does not yet proxy it to Linux editors. A useful proxy needs to keep the project mirror current, start SourceKit from the Mac worker so it can read the USB volume, and translate `file://` document paths in both directions between the Linux checkout and Mac mirror. Running `ssh macbook xcrun sourcekit-lsp` alone would hit the USB volume access failure observed here. Build output and diagnostics are available today through `pipforge build` and its log.

## Agent use

The shared `~/.agents/skills/pipforge/SKILL.md` gives agents the command sequence and output rules. Project-specific build logic belongs in each project's `ios-build.sh`; this repository's [AGENTS.md](AGENTS.md) covers changes to Pipforge itself.
