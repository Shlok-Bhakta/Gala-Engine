---
title: Deliver on every save
description: Use gala watch to test, build, sign, and publish after source edits.
---

Once `gala deliver` succeeds from a project with executable `ios-build.sh` and `ios-test.sh`, start the watch loop:

```sh
gala watch --action deliver
```

Gala runs once immediately, then watches tracked files and non-ignored untracked files. It waits briefly for edits to settle, syncs the changed working tree, runs tests, builds, and publishes after each successful cycle. A failed cycle prints the log path and keeps watching. Stop with Ctrl-C.

`gala watch --action build` is useful while working on the recipe because it returns unsigned IPAs without replacing the current signed delivery. On the ThinkPad, bare `gala watch` repeats the USB `run` action; it needs a paired device and local signing files.

Each new run replaces prior `.gala/runs/` results. Copy any log or report you want to keep before the next edit triggers a cycle. The Mac still keeps `GALA_BUILD_DIR` for incremental builds. See [How Gala works](/getting-started/how-it-works/) for the sync and cache behavior.
