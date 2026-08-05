import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/player/core/line_fallback_manager.dart';

void main() {
  group('LineFallbackManager', () {
    test('skips failed lines and wraps around', () {
      final manager = LineFallbackManager();
      const lines = ['a', 'b', 'c'];

      manager.markFailed('a');
      expect(manager.next(lines), 'b');
      manager.markFailed('b');
      expect(manager.next(lines), 'c');
      expect(manager.next(lines), 'c');
    });

    test('reset makes all lines available again', () {
      final manager = LineFallbackManager();
      const lines = ['a', 'b'];

      manager.markFailed('a');
      manager.markFailed('b');
      expect(manager.hasAvailable(lines), isFalse);

      manager.reset();
      expect(manager.hasAvailable(lines), isTrue);
      expect(manager.next(lines), 'a');
    });

    test('throws when no line can be selected', () {
      final manager = LineFallbackManager();
      expect(() => manager.next(const []), throwsException);

      manager.markFailed('a');
      expect(() => manager.next(const ['a']), throwsException);
    });
  });
}
