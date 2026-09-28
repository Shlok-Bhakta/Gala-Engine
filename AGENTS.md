# Agent instructions

Gala Engine is a single-user tool for building iOS and iPadOS IPAs on a Mac over Tailscale. Ordinary builds return unsigned IPAs; delivery signs on the Mac and serves one current IPA per project to the tailnet. Read `README.md` before changing the CLI or recipe contract.

- Keep the Mac project mirror under the configured external-volume root. Never sync into an existing human checkout.
- The project recipe is `ios-build.sh` in the project root. It runs on the Mac and writes IPAs to `GALA_ARTIFACT_DIR`. Keep reusable build outputs in `GALA_BUILD_DIR`.
- Run `gala doctor` and the UIKit example build when changing transport, worker, or packaging behavior.
- Do not assume an unsigned IPA can be installed without a separate signing step.
- Keep the install server tailnet only and keep IPA, cache, and push state on the external volume.
