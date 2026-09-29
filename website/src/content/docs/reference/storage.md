---
title: Storage and ports
description: Where Gala stores mirrors, caches, current builds, and its three local services.
---

The default Mac root is `/Volumes/BlenderBuild/gala-engine`. Set `GALA_REMOTE_ROOT` or `--root` to another external-volume location when the worker uses a different root. Clients refuse a root that does not match the running worker.

| Path under the Mac root | Purpose |
| --- | --- |
| `projects/<mirror>/source/` | Synced copy of one client checkout. |
| `projects/<mirror>/build/` | Persistent `GALA_BUILD_DIR` cache. |
| `projects/<mirror>/runs/` | Current test and build artifacts. |
| `ota/<mirror>/current.ipa` | Current signed delivery for that project. |
| `subscriptions.json`, `vapid.json` | Web Push subscriptions and keys. |

The client receives logs, reports, and unsigned IPAs under its project's `.gala/runs/<job-id>/`. Gala removes previous runs before a new test, build, run, or delivery. It retains the Mac build cache and source mirror for incremental work. A signed delivery expires after 48 hours.

The worker binds three local services:

| Port | Service | Exposure |
| --- | --- | --- |
| `18730` | rsync daemon for source and artifacts | Localhost; reached through SSH or a local Mac client. |
| `18731` | Worker control API | Localhost; reached through SSH or a local Mac client. |
| `18732` | Private install server | Localhost; Tailscale Serve exposes `/gala` to the tailnet. |

Do not make the control service, rsync daemon, or installer public. See [Security model](/reference/security/).
