---
title: Build recipes
description: The ios-build.sh contract, artifact layout, cache directory, and ways to adapt existing toolchains.
---

Gala finds the nearest `ios-build.sh` above your current directory and treats that folder as the project root. It syncs the working tree to an isolated mirror on the Mac, then runs the script there. The script decides how to build; Gala does not detect Swift, Xcode, React Native, Expo, or CMake.

## The contract

Make `ios-build.sh` executable. It must exit nonzero on failure and place an **unsigned iPhoneOS IPA** anywhere under `GALA_ARTIFACT_DIR` on success. A successful build with no IPA fails validation. The IPA must be a ZIP containing `Payload/<AppName>.app/`.

| Variable | Use |
| --- | --- |
| `GALA_ARTIFACT_DIR` | Fresh output for this run. Put the IPA here; tests can put reports here. |
| `GALA_BUILD_DIR` | Persistent Mac build output, such as DerivedData or CMake and Ninja files. |
| `GALA_JOBS` | Suggested parallelism; the current worker sets it to `2`. |
| `GALA_PLATFORM` | `ios`. |

For Xcode projects, build with `-destination 'generic/platform=iOS'` and `CODE_SIGNING_ALLOWED=NO`, then package the device `.app` into an IPA. The [Xcode tutorial](/tutorials/xcode-project/) has a complete example. For a minimal direct compiler recipe, read the [UIKitHello script](https://github.com/Shlok-Bhakta/Gala-Engine/blob/main/examples/UIKitHello/ios-build.sh).

For React Native or Expo, the recipe can run the normal iOS release build, including bundling and CocoaPods, then copy the resulting unsigned IPA into `GALA_ARTIFACT_DIR`. For CMake or C++ ports, keep the configured build tree under `GALA_BUILD_DIR` and use the project's own packaging step. A new Gala mirror has a new source path, so do not reuse a CMake cache created for a different checkout.

## Test recipe

An executable `ios-test.sh` at the same root runs on the Mac with the same variables. It can perform unit tests, type checks, lint, or other project checks. Write reports under `GALA_ARTIFACT_DIR` to retrieve them. `gala deliver` requires this file and stops if it fails. `gala build` runs without it unless you pass `--gate`.

Gala returns `build.log`, `result.json`, and the IPA under `.gala/runs/<job-id>/`. A new invocation removes previous run directories; copy reports you need to keep. Add `.gala/` to the project's `.gitignore`.
