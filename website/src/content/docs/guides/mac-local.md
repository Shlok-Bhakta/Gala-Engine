---
title: Running on the Mac
description: Use the Mac build worker as a Gala client without an SSH round trip.
---

The Mac that runs the worker can also run Gala commands from a local checkout. Use a local Terminal session so the client can read projects on the external volume.

```sh
ln -sfn /Volumes/BlenderBuild/Projects/Gala-Engine/bin/gala ~/.local/bin/gala
gala doctor --host local
```

When `--host local` is set, Gala talks to the local worker and rsync daemon without SSH. The default `macbook` alias also uses this path when it resolves to the Mac's own hostname, MagicDNS name, or Tailscale address. From a project with an `ios-build.sh` recipe:

```sh
gala build --host local
gala deliver --host local
```

`gala deliver` still requires executable `ios-test.sh` and a matching Mac signing profile. The Mac checkout gets its own Gala mirror under the external-volume root, separate from mirrors belonging to Linux clients. Do not point Gala at a normal human checkout as the mirror.

If `gala doctor --host local` cannot reach the service, check that its LaunchAgent is running and that the configured `GALA_REMOTE_ROOT` matches the service root. For external-volume permission errors, see [Mac worker setup](/setup/mac-worker/).
