---
title: Configuration
description: Client environment variables, recipe directories, and signing inputs.
---

Gala uses command flags and a few environment variables. A client and the Mac worker must agree on the storage root.

| Setting | Default | Meaning |
| --- | --- | --- |
| `GALA_HOST` or `--host` | `macbook` | SSH alias for the Mac; `local` uses a worker on this Mac. |
| `GALA_REMOTE_ROOT` or `--root` | `/Volumes/BlenderBuild/gala-engine` | Mac root for mirrors, caches, signed IPAs, and push state. |
| `GALA_P12` or `--p12` | `~/.config/gala-engine/development.p12` | Linux USB signing certificate and private key. |
| `GALA_PROFILE` or `--profile` | `~/.config/gala-engine/development.mobileprovision` | Matching Linux USB provisioning profile. |
| `GALA_P12_PASSWORD_FILE` | `~/.config/gala-engine/development.p12.password` | Password file for noninteractive USB signing. |

`GALA_P12_PASSWORD` also works, but an environment variable may be visible to local processes and shell history. Keep signing files outside Git. The Mac's OTA signing identity and profile live in its keychain and provisioning profile directories, not in a Gala project.

The Mac worker receives `--root` in its LaunchAgent's `ProgramArguments`. Gala refuses a client root that differs from the running worker's root. The install service is exposed only through Tailscale Serve at `/gala`.

## Variables inside recipes

The worker sets `GALA_ARTIFACT_DIR` for fresh IPA and test report output, `GALA_BUILD_DIR` for reusable build output, `GALA_JOBS` for suggested parallelism, and `GALA_PLATFORM=ios`. See [Build recipes](/guides/recipes/) for the required IPA layout.
