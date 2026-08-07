# Vendored Git dependencies

These sources are committed so local Windows development does not need direct GitHub access during `flutter pub get` or the normal x64 Windows media-kit build.

Pinned upstream revisions:

- `Predidit/media-kit`: `6d744e4ad8af23d29942a7061d8de101972a3707`
- `liuchuancong/flv_lzc`: `030d611dd4ebff40962a13209bb56230853f4f9f`
- `liuchuancong/screen_retriever`: `b246b3963738d6cc159c921764c194c73dbdf2ad`
- `liuchuancong/dart_quickjs`: `0596dfcee794a6af7d6dd0bc6819ba80e0ed655d`
- x64 libmpv archive: `mpv-dev-x86_64-20260623-git-ad59ff1.7z`, SHA-256 `159d7379898e2e2490ab3e0dca233daa5b7389fcd32d4cb8c420399f44284399`

`media_kit_libs_video` is intentionally narrowed to the Windows implementation because this PureLive baseline is Windows-only. The vendored media-kit CMake file is also pointed at the committed x64 libmpv archive instead of downloading it from GitHub at build time.
