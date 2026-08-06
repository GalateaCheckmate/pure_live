import 'dart:async';

import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pure_live/common/global/platform_utils.dart';
import 'package:pure_live/common/index.dart';
import 'package:rxdart/rxdart.dart';

import '../interface/unified_player_interface.dart';
import '../models/player_error_type.dart';
import '../models/player_exception.dart';
import '../models/player_state.dart';

class MediaKitAdapter implements UnifiedPlayer {
  late final Player _player;
  late final VideoController _controller;

  bool _initialized = false;
  bool _disposed = false;
  bool _listenerBound = false;
  bool _isAudioOnly = false;
  String? _currentUrl;

  Future<void> _operationTail = Future<void>.value();
  int _sourceGeneration = 0;

  final _stateSubject =
      BehaviorSubject<PlayerState>.seeded(PlayerState.idle);
  final _playingSubject = BehaviorSubject<bool>.seeded(false);
  final _loadingSubject = BehaviorSubject<bool>.seeded(false);
  final _errorSubject = PublishSubject<PlayerException>();
  final _completeSubject = BehaviorSubject<bool>.seeded(false);
  final _widthSubject = BehaviorSubject<int?>.seeded(null);
  final _heightSubject = BehaviorSubject<int?>.seeded(null);

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<int?>? _widthSub;
  StreamSubscription<int?>? _heightSub;
  StreamSubscription<bool>? _completeSub;
  StreamSubscription<dynamic>? _errorSub;

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationTail = _operationTail.catchError((_) {}).then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  bool _isGenerationCurrent(int generation) {
    return !_disposed && generation == _sourceGeneration;
  }

  @override
  Future<void> init({bool audioOnly = false}) async {
    if (_initialized || _disposed) return;

    _isAudioOnly = audioOnly;
    _listenerBound = false;
    _currentUrl = null;

    try {
      _stateSubject.add(PlayerState.initializing);
      _player = Player();

      if (_player.platform is NativePlayer) {
        final native = _player.platform as dynamic;
        await native.setProperty('force-seekable', 'yes');
        await native.setProperty(
          'protocol_whitelist',
          'httpproxy,udp,rtp,tcp,tls,data,file,http,https,crypto',
        );
        await native.setProperty('demuxer-lavf-probsize', '2097152');
        await native.setProperty('demuxer-lavf-analyzeduration', '10');
        await native.setProperty('network-timeout', '30');

        if (SettingsService.to.player.customPlayerOutput.v) {
          await native.setProperty(
            'ao',
            SettingsService.to.player.audioOutputDriver.v,
          );
        }

        if (SettingsService.to.proxy.enableProxy.v &&
            SettingsService.to.proxy.proxyHost.v.isNotEmpty) {
          final proxyUrl =
              'http://${SettingsService.to.proxy.proxyHost.v}:'
              '${SettingsService.to.proxy.proxyPort.v}';
          await native.setProperty('http-proxy', proxyUrl);
        }

        if (PlatformUtils.isMacOS) {
          await native.setProperty('hwdec', 'no');
        }
      }

      _controller = audioOnly
          ? VideoController(
              _player,
              configuration: const VideoControllerConfiguration(
                vo: 'null',
                hwdec: 'no',
                enableHardwareAcceleration: false,
              ),
            )
          : SettingsService.to.player.playerCompatMode.v
              ? VideoController(
                  _player,
                  configuration: const VideoControllerConfiguration(
                    vo: 'mediacodec_embed',
                    hwdec: 'mediacodec',
                  ),
                )
              : SettingsService.to.player.customPlayerOutput.v
                  ? VideoController(
                      _player,
                      configuration: VideoControllerConfiguration(
                        vo: SettingsService.to.player.videoOutputDriver.v,
                        hwdec: PlatformUtils.isMacOS
                            ? 'no'
                            : SettingsService
                                .to.player.videoHardwareDecoder.v,
                        enableHardwareAcceleration: !PlatformUtils.isMacOS,
                      ),
                    )
                  : VideoController(
                      _player,
                      configuration: VideoControllerConfiguration(
                        enableHardwareAcceleration: PlatformUtils.isMacOS
                            ? false
                            : SettingsService.to.player.enableCodec.v,
                        hwdec: PlatformUtils.isMacOS ? 'no' : null,
                        androidAttachSurfaceAfterVideoParameters: false,
                      ),
                    );

      if (audioOnly) {
        await applyAudioOnlySettings();
      }

      await _bindListeners();
      _initialized = true;
      _stateSubject.add(PlayerState.initialized);
    } catch (error, stackTrace) {
      final exception = PlayerException(
        message: 'MediaKit init failed',
        type: PlayerErrorType.initialization,
        error: error,
        stackTrace: stackTrace,
      );
      _safeAddError(exception);
      throw exception;
    }
  }

  @override
  Future<void> setDataSource(
    String url,
    List<String> playUrls,
    Map<String, String> headers, {
    LiveRoom? room,
    bool audioOnly = false,
  }) {
    final generation = ++_sourceGeneration;

    return _enqueue(() async {
      if (!_isGenerationCurrent(generation)) return;
      if (_currentUrl == url && isPlayingNow) return;

      _isAudioOnly = audioOnly;
      _currentUrl = url;

      try {
        _loadingSubject.add(true);
        _stateSubject.add(PlayerState.preparing);
        _completeSubject.add(false);
        _playingSubject.add(false);
        _widthSubject.add(null);
        _heightSubject.add(null);

        // MediaKit/MPV replaces the current media when open is called. Do not
        // stop the shared renderer here: on Windows that can detach the video
        // output surface and leave every later room stuck on a black frame.
        await _player.open(
          Media(url, httpHeaders: headers),
          play: true,
        );

        // A newer source request is already queued. Let that request replace
        // this source instead of stopping the shared renderer again.
        if (!_isGenerationCurrent(generation)) return;

        final targetVolume = PlatformUtils.isMobile
            ? 1.0
            : room?.getSavedVolume() ?? 1.0;
        await _setVolumeInternal(targetVolume);

        if (_isGenerationCurrent(generation)) {
          _stateSubject.add(PlayerState.ready);
        }
      } catch (error, stackTrace) {
        if (!_isGenerationCurrent(generation)) return;

        final exception = PlayerException(
          message: 'Media open failed',
          type: PlayerErrorType.source,
          error: error,
          stackTrace: stackTrace,
        );
        _safeAddError(exception);
        _stateSubject.add(PlayerState.error);
        throw exception;
      } finally {
        if (_isGenerationCurrent(generation)) {
          _loadingSubject.add(false);
        }
      }
    });
  }

  Future<void> _bindListeners() async {
    if (_listenerBound) return;
    _listenerBound = true;
    await _cancelAllSubscriptions();

    _playingSub = _player.stream.playing.listen(
      (playing) {
        if (_disposed) return;
        _playingSubject.add(playing);
        if (!_loadingSubject.value) {
          _stateSubject.add(
            playing ? PlayerState.playing : PlayerState.paused,
          );
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _emitError(error, stackTrace, PlayerErrorType.native);
      },
    );

    _bufferingSub = _player.stream.buffering.listen(
      (loading) {
        if (_disposed) return;
        _loadingSubject.add(loading);
        if (loading) {
          _stateSubject.add(PlayerState.buffering);
        } else {
          _stateSubject.add(
            _playingSubject.value
                ? PlayerState.playing
                : PlayerState.paused,
          );
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _emitError(error, stackTrace, PlayerErrorType.native);
      },
    );

    _widthSub = _player.stream.width.listen((value) {
      if (!_disposed) _widthSubject.add(value);
    });
    _heightSub = _player.stream.height.listen((value) {
      if (!_disposed) _heightSubject.add(value);
    });

    _completeSub = _player.stream.completed.listen(
      (completed) {
        if (_disposed || !completed) return;
        _completeSubject.add(true);
        _stateSubject.add(PlayerState.completed);
      },
      onError: (Object error, StackTrace stackTrace) {
        _emitError(error, stackTrace, PlayerErrorType.native);
      },
    );

    _errorSub = _player.stream.error.distinct().listen((error) {
      if (_disposed) return;
      final type = _mapErrorType(error.toString());
      _safeAddError(
        PlayerException(message: error.toString(), type: type),
      );
      _stateSubject.add(PlayerState.error);
    });

    _subscriptions.addAll([
      _playingSub!,
      _bufferingSub!,
      _widthSub!,
      _heightSub!,
      _completeSub!,
      _errorSub!,
    ]);
  }

  Future<void> _cancelAllSubscriptions() async {
    for (final subscription in _subscriptions.toList()) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _playingSub = null;
    _bufferingSub = null;
    _widthSub = null;
    _heightSub = null;
    _completeSub = null;
    _errorSub = null;
  }

  void _emitError(
    Object error,
    StackTrace stackTrace,
    PlayerErrorType type,
  ) {
    if (_disposed) return;
    _safeAddError(
      PlayerException(
        message: error.toString(),
        type: type,
        error: error,
        stackTrace: stackTrace,
      ),
    );
    _stateSubject.add(PlayerState.error);
  }

  void _safeAddError(PlayerException exception) {
    if (_disposed || _errorSubject.isClosed) return;
    _errorSubject.add(exception);
  }

  PlayerErrorType _mapErrorType(String error) {
    final lower = error.toLowerCase();
    if (lower.contains('network') ||
        lower.contains('timeout') ||
        lower.contains('io')) {
      return PlayerErrorType.network;
    }
    if (lower.contains('codec') ||
        lower.contains('mediacodec') ||
        lower.contains('decode')) {
      return PlayerErrorType.codec;
    }
    if (lower.contains('404') ||
        lower.contains('source') ||
        lower.contains('open')) {
      return PlayerErrorType.source;
    }
    if (lower.contains('surface') || lower.contains('texture')) {
      return PlayerErrorType.texture;
    }
    return PlayerErrorType.native;
  }

  @override
  Widget getVideoWidget() {
    if (_isAudioOnly) return const SizedBox.shrink();
    return RepaintBoundary(
      child: Video(
        controller: _controller,
        controls: NoVideoControls,
        pauseUponEnteringBackgroundMode:
            !SettingsService.to.app.enableBackgroundPlay.v,
        resumeUponEnteringForegroundMode:
            !SettingsService.to.app.enableBackgroundPlay.v,
      ),
    );
  }

  @override
  Future<void> play() {
    return _enqueue(() async {
      if (!_disposed) await _player.play();
    });
  }

  @override
  Future<void> pause() {
    return _enqueue(() async {
      if (!_disposed) await _player.pause();
    });
  }

  @override
  Future<void> stop() {
    ++_sourceGeneration;
    return _enqueue(() async {
      if (_disposed) return;
      await _player.stop();
      _currentUrl = null;
      _loadingSubject.add(false);
      _playingSubject.add(false);
      _widthSubject.add(null);
      _heightSubject.add(null);
      _stateSubject.add(PlayerState.stopped);
    });
  }

  @override
  Future<void> softStop() {
    ++_sourceGeneration;
    return _enqueue(() async {
      if (_disposed) return;
      try {
        await _player.setVolume(0.0);
        await _player.stop();
      } finally {
        _currentUrl = null;
        _loadingSubject.add(false);
        _playingSubject.add(false);
        _widthSubject.add(null);
        _heightSubject.add(null);
        _stateSubject.add(PlayerState.idle);
      }
    });
  }

  @override
  Future<void> setVolume(double volume) {
    return _enqueue(() async {
      if (!_disposed) await _setVolumeInternal(volume);
    });
  }

  Future<void> _setVolumeInternal(double volume) async {
    final target = (volume * 100).clamp(0.0, 100.0);
    await _player.setVolume(target);
  }

  Future<void> applyAudioOnlySettings() async {
    final native = _player.platform as dynamic;
    await native.setProperty('vid', 'no');
    await native.setProperty('video', 'no');
    await native.setProperty('vo', 'null');
    await native.setProperty('hwdec', 'no');
    await native.setProperty('audio-display', 'no');
  }

  @override
  Future<void> hardDispose() {
    ++_sourceGeneration;
    return _enqueue(() async {
      if (_disposed) return;
      _disposed = true;
      _initialized = false;
      _listenerBound = false;

      await _cancelAllSubscriptions();
      try {
        await _player.stop();
      } catch (_) {}
      try {
        await _player.dispose();
      } catch (_) {}

      await Future.wait([
        _stateSubject.close(),
        _playingSubject.close(),
        _loadingSubject.close(),
        _errorSubject.close(),
        _completeSubject.close(),
        _widthSubject.close(),
        _heightSubject.close(),
      ]);
    });
  }

  @override
  bool get isInitialized => _initialized;

  @override
  bool get isPlayingNow => _playingSubject.value;

  @override
  bool get isReusable => false;

  @override
  Stream<PlayerState> get onStateChanged => _stateSubject.stream;

  @override
  Stream<bool> get onPlaying => _playingSubject.stream;

  @override
  Stream<PlayerException> get onError => _errorSubject.stream;

  @override
  Stream<bool> get onLoading => _loadingSubject.stream;

  @override
  Stream<bool> get onComplete => _completeSubject.stream;

  @override
  Stream<int?> get width => _widthSubject.stream;

  @override
  Stream<int?> get height => _heightSubject.stream;
}
