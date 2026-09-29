---
title: Troubleshooting
description: Diagnose worker, recipe, signing, device, and installer failures.
---

Start with `gala doctor`. It checks Xcode, the iPhoneOS SDK, the worker's storage root, rsync, and the private installer. For a failed recipe, open the printed `test.log` or `build.log` under `.gala/runs/<job-id>/`; Gala returns a nonzero status on failure.

## Worker and sync

- **Worker unreachable:** Check Tailscale and the client's SSH alias. On the Mac, confirm the LaunchAgent is running. For a local Mac client, try `gala doctor --host local` from a local Terminal session.
- **Root mismatch:** Set `GALA_REMOTE_ROOT` or `--root` to the same root used by `mac-service`. Do not redirect the mirror into a normal checkout.
- **External-volume access error:** The worker's Python process may need Full Disk Access. See [Mac worker setup](/setup/mac-worker/#full-disk-access).
- **Unexpected source transfer:** `gala sync --dry-run` shows changes. `gala build --checksum` compares contents when timestamps changed after a branch switch.

## Builds and signing

- **No IPA found:** Check that `ios-build.sh` writes an unsigned device IPA under `GALA_ARTIFACT_DIR`. `gala build` rejects an empty artifact directory or malformed `Payload/*.app` ZIP.
- **Test gate failed:** `gala deliver` requires executable `ios-test.sh`. Read `test.log`, fix the check, then retry.
- **Signing failed:** Confirm a nonexpired profile covers the bundle ID and target devices and its certificate and private key are in the Mac keychain. If the keychain does not grant `codesign` access, follow [Signing and profiles](/setup/signing/).
- **HTTPS check failed:** Verify Tailscale Serve points `/gala` to the local install server and is reachable from the client. Do not report an install URL from a failed command.

## On the device

If the install prompt does not appear, open the returned URL in Safari with Tailscale connected and tap **Install**. If the IPA transfers but no app appears, iOS may still be finishing or may have rejected the profile. Check the device's provisioning and trust settings. Gala cannot read the final installation status from iOS.
