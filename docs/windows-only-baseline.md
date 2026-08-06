# Windows-only baseline

PureLive currently targets Windows x64 as its only supported Flutter platform.

## Platform scope

- Android, iOS, Linux and macOS runner projects have been removed.
- CI and release automation build Windows only.
- Application startup initializes the Windows desktop window manager,
  single-instance guard, brightness integration and launch-at-startup support.
- `PlatformUtils` remains as a compatibility facade for older call sites, but
  resolves platform decisions to Windows desktop behavior.
- Mobile storage-permission handling and its direct dependencies have been
  removed from the recorder path.

## Runtime baseline

- Required database and settings services are awaited before the first frame.
- FFmpeg, recording and account services remain deferred until startup finishes.
- Recorder tasks persist their lifecycle state and can recover after restart.
- Favorite-room refresh runs requests concurrently and publishes one atomic UI
  update after all available results are merged.
- Danmaku WebSocket connections explicitly use the configured application proxy
  or a direct connection instead of inheriting stale environment proxies.

## Validation strategy

Routine validation uses **Windows Quick Check**:

```text
flutter analyze --no-pub
flutter test --no-pub
```

The manually triggered **Windows Full Build** also builds the Windows release,
uploads the portable application and records a package-size baseline.

For an interactive local runtime baseline after building on Windows:

```powershell
flutter build windows --release
./tool/windows_baseline.ps1
```

The default report is written to `build/windows-baseline.json`.
