# PureLive Windows-only baseline

PureLive is now developed and distributed as a Windows-only Flutter desktop application.

## Supported target

- Windows x64
- Flutter 3.44.8
- Dart compatible with `^3.10.4`
- FFmpeg Windows bundle 0.10.5

## Removed platform projects

The Android, iOS, Linux and macOS native projects have been removed. The repository does not carry a Web runner.

## Windows-only application lifecycle

- The application bootstrap always initializes the Windows desktop window manager.
- MediaKit is the fixed default playback engine during startup.
- Windows single-instance handling is part of the required startup chain.
- Windows brightness and launch-at-startup initialization run without cross-platform branches.
- The obsolete mobile platform manager and Android shared-media bootstrap have been removed.
- `PlatformUtils` remains temporarily as a compatibility facade returning Windows constants while older call sites are migrated.

## Dependency cleanup

Removed platform-specific build and runtime configuration includes:

- Android, iOS, Linux and macOS MediaKit overrides
- Android, iOS and macOS icon generation
- Android and macOS FFmpeg bundles
- Android intents, mobile orientation, mobile scanner and mobile floating-window packages
- Mobile share-handler integration
- macOS DMG packaging

The remaining Android recorder storage-permission block is captured in:

`development/patches/windows-only-recorder-permission-cleanup.diff`

It is staged as a patch because the recorder lifecycle branch contains newer concurrent changes. The patch removes the Android permission flow and its `permission_handler` and `device_info_plus` dependencies when the recorder branch is integrated.

## Development policy

Development commits use `[skip ci]` until the Windows baseline, player lifecycle and recorder lifecycle branches are consolidated. GitHub Actions and the final Windows build are run only after that consolidation.
