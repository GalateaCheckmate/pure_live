import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/player/core/player_pool.dart';
import 'package:pure_live/player/interface/unified_player_interface.dart';
import 'package:pure_live/player/models/player_engine.dart';
import 'package:pure_live/player/models/player_exception.dart';
import 'package:pure_live/player/models/player_state.dart';

void main() {
  group('PlayerPool', () {
    test('reuses players only for the same engine and audio mode', () async {
      var created = 0;
      final pool = PlayerPool(
        factory: (_) async => _FakePlayer(++created),
      );

      final videoA = await pool.getPlayer(PlayerEngine.mediaKit);
      final videoB = await pool.getPlayer(PlayerEngine.mediaKit);
      final audio = await pool.getPlayer(PlayerEngine.mediaKit, audioOnly: true);

      expect(identical(videoA, videoB), isTrue);
      expect(identical(videoA, audio), isFalse);
      expect(created, 2);
      expect((videoA as _FakePlayer).audioOnly, isFalse);
      expect((audio as _FakePlayer).audioOnly, isTrue);
    });

    test('coalesces concurrent creation for the same key', () async {
      var created = 0;
      final gate = Completer<void>();
      final pool = PlayerPool(
        factory: (_) async {
          created++;
          await gate.future;
          return _FakePlayer(created);
        },
      );

      final first = pool.getPlayer(PlayerEngine.mediaKit);
      final second = pool.getPlayer(PlayerEngine.mediaKit);
      gate.complete();

      expect(identical(await first, await second), isTrue);
      expect(created, 1);
    });

    test('removing an engine disposes both audio and video instances', () async {
      final players = <_FakePlayer>[];
      final pool = PlayerPool(
        factory: (_) async {
          final player = _FakePlayer(players.length + 1);
          players.add(player);
          return player;
        },
      );

      await pool.getPlayer(PlayerEngine.mediaKit);
      await pool.getPlayer(PlayerEngine.mediaKit, audioOnly: true);
      await pool.removeFromCache(PlayerEngine.mediaKit);

      expect(players, hasLength(2));
      expect(players.every((player) => player.disposed), isTrue);
    });
  });
}

class _FakePlayer implements UnifiedPlayer {
  _FakePlayer(this.id);

  final int id;
  bool audioOnly = false;
  bool disposed = false;

  @override
  Future<void> init({bool audioOnly = false}) async {
    this.audioOnly = audioOnly;
  }

  @override
  Future<void> hardDispose() async {
    disposed = true;
  }

  @override
  bool get isInitialized => !disposed;

  @override
  bool get isPlayingNow => false;

  @override
  bool get isReusable => true;

  @override
  Stream<bool> get onComplete => const Stream.empty();

  @override
  Stream<PlayerException> get onError => const Stream.empty();

  @override
  Stream<bool> get onLoading => const Stream.empty();

  @override
  Stream<bool> get onPlaying => const Stream.empty();

  @override
  Stream<PlayerState> get onStateChanged => const Stream.empty();

  @override
  Stream<int?> get width => const Stream.empty();

  @override
  Stream<int?> get height => const Stream.empty();

  @override
  Widget getVideoWidget() => const SizedBox.shrink();

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> setDataSource(
    String url,
    List<String> playUrls,
    Map<String, String> headers, {
    LiveRoom? room,
    bool audioOnly = false,
  }) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> softStop() async {}

  @override
  Future<void> stop() async {}
}
