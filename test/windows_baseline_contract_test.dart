import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String readRepositoryFile(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: 'Missing repository file: $path');
  return file.readAsStringSync();
}

void main() {
  group('Windows-only baseline contracts', () {
    test('required services are awaited before desktop initialization', () {
      final source = readRepositoryFile('lib/common/global/initialized.dart');
      final requiredIndex = source.indexOf('await InitialServices.initRequiredServices();');
      final desktopIndex = source.indexOf('await DesktopManager.initialize();');

      expect(requiredIndex, greaterThanOrEqualTo(0));
      expect(desktopIndex, greaterThan(requiredIndex));
      expect(source, contains('InitialServices.scheduleDeferredServices();'));
    });

    test('common barrel does not export itself', () {
      final source = readRepositoryFile('lib/common/index.dart');

      expect(source, isNot(contains("export 'package:pure_live/common/index.dart';")));
    });

    test('release workflow contains only the Windows build job', () {
      final source = readRepositoryFile('.github/workflows/release.yml');

      expect(source, contains('build-windows:'));
      expect(source, isNot(contains('build-android:')));
      expect(source, isNot(contains('build-macos:')));
    });

    test('Windows CI analyzes, tests, builds and records a baseline', () {
      final source = readRepositoryFile('.github/workflows/windows-ci.yml');

      expect(source, contains('flutter analyze'));
      expect(source, contains('flutter test'));
      expect(source, contains('flutter build windows --release'));
      expect(source, contains('windows_baseline.ps1'));
    });
  });
}
