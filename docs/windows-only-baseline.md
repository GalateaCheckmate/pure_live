# Windows-only baseline

PureLive now targets Windows x64 as its only supported Flutter platform.

## Platform scope

- The Android, iOS, Linux and macOS runner projects have been removed.
- CI and release automation build Windows only.
- Application startup always initializes the Windows desktop window manager,
  single-instance guard, brightness integration and launch-at-startup support.
- The mobile platform manager and Android shared-media bootstrap have been removed.
- `PlatformUtils` remains as a compatibility facade for older call sites, but
  resolves all platform decisions to Windows desktop behavior.

## Runtime baseline

- Required database and settings services are awaited before the first frame.
- FFmpeg, recording and account services remain deferred until startup finishes.
- The invalid template counter test is replaced with architecture contract tests.
- The self-export in `lib/common/index.dart` is removed.
- A PowerShell baseline collector records package size and can optionally record
  process startup and memory data on a real Windows desktop.

## Favorite refresh pipeline

Favorite-room refresh now starts all valid room-detail requests together instead
of waiting for small sequential batches. Individual room failures and 20-second
request timeouts are isolated, successful results are merged into the latest
favorites snapshot, and the observable list is published only once after the
whole refresh finishes. A generation token prevents an older refresh from
overwriting a newer request.

## Deferred recorder cleanup

The recorder branch contains newer lifecycle work than this baseline branch.
The Windows-only removal of Android storage permission handling is staged in:

```text
development/patches/windows-only-recorder-permission-cleanup.diff
```

Apply that patch while integrating the recorder branch instead of restoring the
older recorder controller from this branch.

## Final validation strategy

Development commits use `[skip ci]`. After the Windows baseline, player and
recorder branches are integrated, run the Windows workflow once for dependency
resolution, static analysis, tests and the release build.

For an interactive local runtime baseline after building on Windows:

```powershell
flutter build windows --release
./tool/windows_baseline.ps1
```

The default report is written to `build/windows-baseline.json`.
