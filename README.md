# Pipforge

Build unsigned iPhone and iPad IPAs on a Mac while working on Linux. Pipforge syncs a project over SSH, runs its `ios-build.sh` on the Mac, and copies the IPA and build log back. Tailscale supplies the private network; Pipforge uses your existing SSH setup.

Pipforge is deliberately small. There is no daemon, account, web UI, simulator, or GitHub push in the build path. It builds the files in your current working tree, including uncommitted edits.

## One-time setup

On the Mac, install Xcode and its iPhoneOS SDK. Keep the bulk build volume mounted. On the client, make sure `ssh macbook` reaches the Mac over Tailscale. If your SSH alias has another name, use `PIPFORGE_HOST` or `--host`.

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

The default Mac storage root is `/Volumes/BlenderBuild/pipforge`. Override it with `PIPFORGE_REMOTE_ROOT` if this Mac uses another bulk volume. Pipforge creates its own project mirrors under that root; it never syncs into your normal Mac checkout.

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

For a real minimal UIKit example:

```sh
cd ~/Projects/Pipforge/examples/UIKitHello
pipforge build
```

The example produces an unsigned arm64 iPhone/iPad IPA without an Xcode project or simulator.

## Sync behavior

Normal `rsync` uses file size and modification time to decide which paths need inspection. For a changed file, it transfers differences rather than blindly copying the entire tree. A Git branch switch may update timestamps and cause some otherwise identical files to be sent again. Pipforge has no cross-branch content store on the client or Mac.

Use `pipforge sync --dry-run` to see what would change. Use `pipforge build --checksum` when timestamp churn is causing excess transfer; that compares file contents on both machines, but reads the whole tree on both sides. The default is faster for ordinary edit-build cycles.

Pipforge excludes Git metadata, `.pipforge`, Nix/Node/Expo/Xcode build directories, and patterns from each `.gitignore`. It deletes synced files removed from the client source mirror while preserving `PIPFORGE_BUILD_DIR` and past run artifacts. Large dependencies already installed on the Mac can live outside the mirror and be referenced by `ios-build.sh`.

## Existing projects

- **Native SwiftUI/UIKit:** Put `xcodebuild` in `ios-build.sh`, set a stable `-derivedDataPath` inside `PIPFORGE_BUILD_DIR`, target `generic/platform=iOS`, and package the device `.app` as `Payload/App.app` in the IPA. The project decides whether signing happens on the Mac or later on Linux.
- **Blender port:** Reuse the device CMake/Ninja and `package_sideload_ipa.py` commands from its current PR preview workflow. Keep the dependency prefix and revision-matched host tools on the Mac's bulk volume. Give Pipforge's mirror a new CMake build directory because CMake caches the source path.
- **Expo:** Prebuild the iOS project on the Mac, then run its Xcode build in `ios-build.sh`. `eas build --local` is an alternative for EAS parity, but Expo's local mode does not support caching.

The Mac serializes build recipes across all Pipforge projects, which fits its 8 GB of RAM. Source sync can happen before a build slot becomes free.

## Agent use

The shared `~/.agents/skills/pipforge/SKILL.md` gives agents the command sequence and output rules. Project-specific build logic belongs in each project's `ios-build.sh`; this repository's [AGENTS.md](AGENTS.md) covers changes to Pipforge itself.
