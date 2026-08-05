import '../models/player_engine.dart';
import '../interface/unified_player_interface.dart';

class PlayerPool {
  final Map<_PlayerPoolKey, UnifiedPlayer> _cache = {};
  final Map<_PlayerPoolKey, Future<UnifiedPlayer>> _pending = {};

  final Future<UnifiedPlayer> Function(PlayerEngine) factory;

  PlayerPool({required this.factory});

  Future<UnifiedPlayer> getPlayer(PlayerEngine engine, {bool audioOnly = false}) async {
    final key = _PlayerPoolKey(engine, audioOnly);
    final cached = _cache[key];
    if (cached != null) return cached;

    final pending = _pending[key];
    if (pending != null) return pending;

    final creation = _createPlayer(key);
    _pending[key] = creation;
    try {
      return await creation;
    } finally {
      _pending.remove(key);
    }
  }

  Future<UnifiedPlayer> _createPlayer(_PlayerPoolKey key) async {
    final player = await factory(key.engine);
    try {
      await player.init(audioOnly: key.audioOnly);
      _cache[key] = player;
      return player;
    } catch (_) {
      await player.hardDispose();
      rethrow;
    }
  }

  Future<void> removeFromCache(PlayerEngine engine, {bool? audioOnly}) async {
    final keys = _cache.keys
        .where((key) => key.engine == engine && (audioOnly == null || key.audioOnly == audioOnly))
        .toList(growable: false);

    for (final key in keys) {
      final player = _cache.remove(key);
      if (player != null) {
        await player.hardDispose();
      }
    }
  }

  Future<void> disposeAll() async {
    final players = _cache.values.toSet().toList(growable: false);
    _cache.clear();
    _pending.clear();

    for (final player in players) {
      await player.hardDispose();
    }
  }
}

class _PlayerPoolKey {
  const _PlayerPoolKey(this.engine, this.audioOnly);

  final PlayerEngine engine;
  final bool audioOnly;

  @override
  bool operator ==(Object other) {
    return other is _PlayerPoolKey && other.engine == engine && other.audioOnly == audioOnly;
  }

  @override
  int get hashCode => Object.hash(engine, audioOnly);
}
