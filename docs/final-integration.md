# PureLive Windows final integration

This branch is the final integration candidate for the Windows-only PureLive baseline.

It combines:

- Windows-only project structure, startup, CI and release configuration;
- player lifecycle and live-room switching stability fixes;
- recorder lifecycle, FFmpeg argument and persistence reliability fixes;
- concurrent favorite-room refresh with atomic UI updates;
- deferred service initialization without duplicate GetX registrations.

The Windows CI workflow is the integration gate for dependency resolution, static analysis, tests, release compilation and portable artifact generation.
