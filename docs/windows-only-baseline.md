# Windows-only baseline

This branch establishes a safe Windows-only development baseline without removing
the existing player engines, account services, recording features or live
platform integrations.

## Scope

- Required database and settings services are awaited before the first frame.
- FFmpeg, recording and account services remain deferred until startup finishes.
- GitHub CI analyzes, tests and builds only the Windows target.
- Release automation produces Windows packages only.
- The invalid template counter test is replaced with architecture contract tests.
- The self-export in `lib/common/index.dart` is removed.
- A PowerShell baseline collector records package size and can optionally record
  process startup and memory data on a real Windows desktop.

## CI baseline

Every push to `master` or `agent/**` produces:

- a Windows release directory artifact;
- `windows-baseline.json` containing release size and file count.

GitHub-hosted runners use `-SkipLaunch` because they are not a reliable
interactive desktop benchmark.

## Local runtime baseline

After building the release on Windows, run:

```powershell
flutter build windows --release
./tool/windows_baseline.ps1
```

The default report is written to:

```text
build/windows-baseline.json
```

It contains:

- time until a responsive main window is detected;
- working-set memory after the warm-up period;
- private memory;
- consumed CPU time;
- release directory size and file count.

Refresh latency and playback CPU/GPU usage require an interactive test against
real live rooms, so they should be recorded separately after this structural
baseline is green.
