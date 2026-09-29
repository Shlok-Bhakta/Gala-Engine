---
title: Security model
description: Where Gala sends source and IPAs, what stays private, and how signing material is handled.
---

Gala is a single-user tool for a Mac and devices you control. Source files move from the client to the Mac worker through SSH and rsync. The worker's control, rsync, and install services bind to `127.0.0.1`; Tailscale Serve exposes only the installer to the tailnet. Do not enable Funnel for `/gala`.

The Mac keeps project mirrors, build caches, the current signed IPA for each project, and Web Push state under the configured external-volume root. Build and test artifacts return to `.gala/runs/` on the client. Gala does not upload source or signed IPAs to GitHub as part of the build path.

Gala signs OTA builds with a matching profile and certificate in the Mac keychain. The profile must list the target devices. For USB installs from Linux, the client uses its own `.p12` and `.mobileprovision`; keep them outside Git and restrict access to the password file. An unsigned IPA returned by `gala build` is not directly installable.

The installer is private to tailnet members, but a tailnet address alone does not authorize an iOS install: the signed profile must also cover the device. A successful transfer is not proof that iOS completed installation. Confirm the app on the device. See [Delivery and installs](/guides/delivery/).
