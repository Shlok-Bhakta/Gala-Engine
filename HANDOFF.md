# Gala Engine handoff, 2026-10-04

Another agent used Gala from Linux and filed six complaints. This session fixed five of them, the sixth was dropped on purpose (see below), and it also added a build queue, Mac cleanup, and a code review pass. Nothing is committed yet.

## Follow-up: delivery of an existing IPA

The owner asked for agents to control their own build cycle and use Gala only for signing and delivery. This follow-up implements that flow and makes skill updates part of the working instructions.

- `gala push /path/to/app.ipa` is an alias for `gala publish`. Both accept an explicit IPA from any directory without `ios-build.sh` or `ios-test.sh`. They only prepare storage, upload, sign on the Mac, and publish with the existing notification path. They never sync source, test, or build.
- Existing Gala projects keep their delivery identity. Without a recipe, the current directory identifies the delivery and stores `.gala/` results. `--name my-app` gives a stable name across directories or machines. Omitting the IPA still selects the latest Gala build and requires a recipe project.
- Publishing now takes the same client lock as building, validates input before contacting the worker, and records prepare/upload/publish timings. `--json` works for both command names on success and failure.
- Six new publish regression tests cover external IPAs, recipe identity, latest-artifact selection, invalid input, JSON errors, and no-argument behavior. Queue tests now mock the Xcode identity so the worker unit tests can run on Linux too. The Mac and crabcake each pass all 22 Python tests. APNs passes all 4 Node tests on the Mac.
- `gala doctor` passed from this Mac and crabcake. The UIKitHello build passed. Crabcake then pushed its IPA from `/tmp/gala-existing-ipa.0rIpQk`, which contains no build or test recipes. Delivery took 1.4 seconds, and an HTTPS download of the signed IPA matched its SHA-256. Device installation and launch were not checked.
- Validation delivery: `https://shloks-macbook-air.taildb44.ts.net/gala/uikithello-existing-ipa-validation/`. Detailed result: `/Volumes/BlenderBuild/gala-engine/existing-ipa-validation-result.json`. This is an ordinary delivery and expires after 48 hours.
- Updated the README and `~/.agents/skills/gala-engine/SKILL.md` with the existing-IPA workflow. The skill now requires documenting Gala behavior changes and syncing the changed skill to crabcake, checking hashes, and recording offline clients here. The skill validator passed on crabcake.
- Copied the changed CLI, README, publish and queue tests, and this handoff to crabcake. Synced the Gala skill to crabcake and kiwi, with matching SHA-256 hashes. The Mac CLI symlink already points to this checkout. ThinkPad timed out over SSH and still needs the updated CLI and skill when online.
- These changes use the existing worker API and signing path, so the running Mac service needed no restart. Its service.py snapshot still contains the prior CLI code; copy the current `bin/gala` there when doing the next service deployment. The earlier handoff work and this follow-up remain uncommitted. Do not reset crabcake's uncommitted checkout while syncing updates.

## Handoff follow-through

The owner asked to continue the older next steps as well as the existing-IPA request.

- Added the simulator and helper reaper to startup and hourly housekeeping. `SIMULATOR_MAX_AGE` is 12 hours. It uses simctl's `lastBootedAt`, with persisted first-observation fallback. A queue lock prevents a Gala job starting during cleanup, and publishing also prevents cleanup. Old orphaned helpers must have unchanged CPU usage between checks, belong to this user, have no live children, and still match their original PID/start time before termination. Includes Xcode's newer `SWBBuildService` name. Every action is logged; cleanup errors do not stop the worker.
- Deployed the reaper and observed it shut down the two old simulators and close Simulator.app. The Mac's internal free space rose to 53 GB. The refreshed doctor and UIKitHello build passed.
- Tried launchd with external stdout/stderr, which failed with EX_CONFIG. Tried a local diagnostic log, which let Python start, but a process sample showed it hanging in `open` while reading the USB `service.py`. The TCC entry still names an older Homebrew Python version. Requested Full Disk Access for `/opt/homebrew/bin/python3` from the owner. Restored the manual service while that setting is pending. The plist keeps `/dev/null` for startup; Python now redirects its own stdout/stderr to external `service.log` after checking volume access. Pending retry after the setting changes.
- Removed repeated installer expiry logic, extracted project-list/manifest/file-streaming helpers, and cached Tailscale DNS for 60 seconds. Legacy `/build` and `/test` endpoints and `build.lock` stay until ThinkPad is updated, as the older handoff requires.
- Updated the recipes in MB-Notes, MB-Document-Scanner, MB-converter, MB-converter-feature-block, MB-Music-Tools, MB-Rice, QR-Scanner, d-zero, and keyboard-test. Xcodebuild package caches now stay beside Gala's DerivedData on the external volume. Gala-only recipes require `GALA_BUILD_DIR` instead of falling back to internal scratch. Notes and Document Scanner create temporary iPhone simulators and shut down/delete them on success, failure, or a handled signal. QR Scanner's archive script still supports CI without Gala and places the package cache beside its selected DerivedData.
- All 12 changed recipe files passed shell syntax checks. Temporary-device cleanup and preservation of xcodebuild's exit status passed with statuses 0 and 7 for both Notes and Document Scanner. The real Document Scanner Gala test passed in 106.6 seconds. Notes and the native Gala gated build are still being verified.
- Current repo checks pass 34 Python tests and 4 Node APNs tests. Worker tests now close recipe stdout pipes, eliminating the earlier ResourceWarnings. The updated Gala skill documents worker upkeep, recipes, upgrade precautions, and skill synchronization, and has been synced to crabcake and kiwi.
- App recipe edits are in their own local checkouts. Several recipes are ignored local configuration; other app source changes were preserved. Do not commit or reset unrelated app work.

## What changed

All of this is in `bin/gala`. It is deployed as `/Volumes/BlenderBuild/gala-engine/service.py`, and the running service has the latest copy.

- **Build queue.** The Mac runs one job at a time across every project and client, because it has 8 GB of RAM. Clients print their queue position and what is ahead of them, then stream the log live. `gala queue` shows what is running. Ctrl-C or killing the client cancels its job. If a client vanishes, the Mac drops its queued job after 2 minutes and stops its running job after 5.
- **Timings and `--json`.** Every project command ends with a timing line for prepare, sync, queue, test, build, fetch, and publish. With `--json`, stdout is a single object and progress goes to stderr. That object is also saved to `.gala/last-result.json`.
- **Test caching.** `deliver` and `--gate` skip `ios-test.sh` when the client source and the Xcode version are unchanged since the last pass. `--retest` forces it. An explicit `gala test` always runs.
- **`gala exec -- '<cmd>'`.** Runs a command in the Mac mirror and fetches anything written to `$GALA_ARTIFACT_DIR`. A round trip is about 3 s from crabcake.
- **Device reports.** Copy `examples/GalaReporter/GalaReporter.swift` into an app. It sends console output, screenshots, and crash diagnostics to `/gala/<project>/report`. `gala reports` fetches them. Mac signing writes `GalaReportURL` into the app's `Info.plist`. The upload was tested over Tailscale HTTPS, and the Swift file type-checks, but it has not run inside a real app yet.
- **Quiet delivery.** `gala deliver` prints `Delivered <app> build N: <url>` and nothing about notifications, as requested.
- **Metal.** `xcrun metal` was failing even though Xcode listed the component as installed. Running `xcodebuild -downloadComponent MetalToolchain` fixed it. `gala doctor` now checks Metal, free disk space, and the queue.
- **Mac cleanup.**
  - Scratch directories are wiped when the service starts.
  - Mirrors unused for 21 days are deleted.
  - The Mac keeps 50 logs, 20 crashes, and 20 screenshots per project.
  - `service.log` is trimmed at 20 MB.
  - The module cache is cleared when Xcode changes.
  - Jobs get `TMPDIR`, the clang module cache, and a fixed `PATH`, with the first two on the external volume.
- **Review fixes.**
  - Build numbers are tracked per bundle ID in `build-numbers.json`.
  - Publishes run one at a time, and `current.json` is written atomically.
  - A push failure can no longer fail a finished delivery.
  - The client reuses one SSH connection.
  - A second service instance fails before touching scratch directories.
  - `gala run` checks its USB tools before building.
  - IPAs in subfolders are found.
  - Expired web push subscriptions are removed.
- **Tests.** `tests/test_queue.py` is new. `python3 -m unittest discover -s tests` passes 16 of 16, and `node --test mac/apns.test.js` passes 4 of 4.
- **Docs.** The README covers all of the above. The shared skill at `~/.agents/skills/gala-engine/SKILL.md` was rewritten short and synced to the Mac, crabcake, and kiwi.

## Where things are installed

| Machine | CLI | Skill |
|---|---|---|
| Mac | `~/.local/bin/gala` is a symlink to this repo | updated |
| crabcake | the changed files are copied into `~/Projects/Gala-Engine`, which shows them as uncommitted | updated |
| kiwi | no CLI | updated |
| ThinkPad | old version; it was off | not updated |

## Storage

The internal disk went from 21 GB free to 50 GB free.

Deleted:

| Item | Size |
|---|---|
| Xcode DerivedData | 17 GB |
| `$TMPDIR/mbnotes-test` | 3 GB |
| SwiftPM cache | 2.6 GB |
| npm and npx caches | 2.1 GB |
| bun cache | 1.9 GB |
| clang ModuleCache | 1.1 GB |
| Homebrew old versions | 1 GB |
| Old Playwright browsers | 0.5 GB |
| An old T3 installer | 0.1 GB |
| `/private/tmp` entries older than 2 days | not sized |

Left alone:

| Item | Size | Reason |
|---|---|---|
| 18 simulator devices | 41 GB | two were booted and in use |
| `/private/tmp` agent scratch from the last 2 days | about 12 GB | other sessions may be using it |
| watchOS 26.5 runtime | 7 GB | needs the owner's call |
| Trash | 1 GB | needs the owner's call |
| `~/.t3` backups and `~/.codex/sessions` | 2 GB | could be moved to the external drive |
| `/Library/Developer/CommandLineTools` | 1.9 GB | needs sudo |

Gala's own data is on the external drive. Internal-disk use from Gala now comes mostly from project test scripts that boot simulators: mb-notes and mb-document-scanner pick the 6 GB iPad Pro 13.

## Decisions made

- **Notification counts.** The client does not report who was notified. Agents only learn that the build was delivered and get the install URL.
- **Native app notifications.** Skipped for now. The owner will use the web app's push from the phone's Home Screen. The blocker, for whenever this comes back: the push-enabled profile for `com.galaengine.app` was made with a certificate whose private key is not in the Mac keychain. Regenerate the profile with the current dev cert (`C5289232…`) to unblock it.

## Remaining steps

1. Enable Full Disk Access for the current Homebrew Python, then finish launchd migration. When Gala's queue is empty, stop the manual service, copy the current `bin/gala` to `/Volumes/BlenderBuild/gala-engine/service.py`, and bootstrap `~/Library/LaunchAgents/com.gala.engine.plist`. Verify actual worker health with `gala doctor` and a UIKitHello build; a loaded job is insufficient. Python opens the external service log itself.
2. Finish recording the Notes and native Gala validation results, commit/push this Gala checkout, and bring crabcake to the resulting commit. Preserve its copied work in a named stash before pulling rather than resetting uncommitted files.
3. ThinkPad is still offline. Update its Gala CLI and skill when reachable, then remove the legacy `/build` and `/test` API and the unused `build.lock` file.
4. Before the macOS, Xcode, and SDK upgrade, download and expand the Xcode `.xip` on the external drive. After upgrading, remove the old unused simulator dyld cache `/Library/Developer/CoreSimulator/Caches/dyld/25F80`, re-run `xcodebuild -downloadComponent MetalToolchain`, add the desired iPhone simulator runtime, and run `gala doctor`. No operating-system or SDK upgrade was requested in this follow-through.
5. Native push remains intentionally deferred. Regenerate the explicit `com.galaengine.app` profile with the current development certificate only when returning to native notifications. The owner's current notification path is the Home Screen web app.
