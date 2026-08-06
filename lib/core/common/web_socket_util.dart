import 'dart:async';
import 'dart:io';

import 'package:pure_live/common/services/settings_service.dart';
import 'package:web_socket_channel/io.dart';

enum SocketStatus { connected, failed, closed }

class WebScoketUtils {
  SocketStatus status = SocketStatus.closed;

  /// 链接
  final String url;

  /// 备用链接
  final String? backupUrl;

  /// 心跳时间
  final int heartBeatTime;

  /// 接收到信息
  final Function(dynamic)? onMessage;

  /// 连接关闭
  final Function(String msg)? onClose;

  /// 尝试重连
  final Function()? onReconnect;

  /// 准备就绪
  final Function()? onReady;

  /// 心跳
  final Function()? onHeartBeat;

  /// 请求头
  Map<String, dynamic>? headers;
  WebScoketUtils({
    required this.url,
    required this.heartBeatTime,
    this.onMessage,
    this.onClose,
    this.onReconnect,
    this.onReady,
    this.onHeartBeat,
    this.headers,
    this.backupUrl,
  });
  IOWebSocketChannel? webSocket;
  HttpClient? _httpClient;
  Timer? heartBeatTimer;

  /// 重连次数
  int reconnectTime = 0;
  Timer? reconnectTimer;

  /// 最大重连次数
  int maxReconnectTime = 5;

  StreamSubscription<dynamic>? streamSubscription;

  HttpClient _createHttpClient() {
    final client = HttpClient();
    client.findProxy = (uri) {
      try {
        final proxy = SettingsService.to.proxy;
        final host = proxy.appProxyHost.value.trim();
        final port = proxy.appProxyPort.value;
        if (proxy.enableAppProxy.value &&
            host.isNotEmpty &&
            port > 0 &&
            port <= 65535) {
          return 'PROXY $host:$port';
        }
      } catch (_) {
        // Settings may be unavailable during very early startup. In that case,
        // keep danmaku connections independent from stale environment proxies.
      }
      return 'DIRECT';
    };
    return client;
  }

  /// 连接
  void connect({bool retry = false}) async {
    close();
    try {
      var wsurl = url;
      if (backupUrl != null && backupUrl!.isNotEmpty && retry) {
        wsurl = backupUrl!;
      }
      _httpClient = _createHttpClient();
      webSocket = IOWebSocketChannel.connect(
        wsurl,
        connectTimeout: const Duration(seconds: 10),
        headers: headers,
        customClient: _httpClient,
      );

      await webSocket?.ready;
      ready();
    } catch (e) {
      _httpClient?.close(force: true);
      _httpClient = null;
      if (!retry) {
        connect(retry: true);
        return;
      }
      onError(e, e);
    }
  }

  /// 连接完成
  void ready() {
    status = SocketStatus.connected;

    streamSubscription = webSocket?.stream.listen(
      (data) => receiveMessage(data),
      onError: (e, s) => onError(e, s),
      onDone: onDone,
    );

    onReady?.call();
    initHeartBeat();
  }

  void initHeartBeat() {
    heartBeatTimer = Timer.periodic(Duration(milliseconds: heartBeatTime), (
      timer,
    ) {
      onHeartBeat?.call();
    });
  }

  void receiveMessage(dynamic data) {
    // 接受到一条信息才算重连成功
    reconnectTime = 0;
    onMessage?.call(data);
  }

  void onError(dynamic e, dynamic s) {
    status = SocketStatus.failed;
    onClose?.call(e.toString());
  }

  void onDone() {
    if (status == SocketStatus.closed) {
      return;
    }
    onReconnect?.call();
    reconnect();
  }

  void sendMessage(dynamic message) {
    if (status == SocketStatus.connected) {
      webSocket?.sink.add(message);
    }
  }

  void close() {
    status = SocketStatus.closed;

    streamSubscription?.cancel();
    streamSubscription = null;

    reconnectTimer?.cancel();
    reconnectTimer = null;

    webSocket?.sink.close();
    webSocket = null;

    _httpClient?.close(force: false);
    _httpClient = null;

    heartBeatTimer?.cancel();
    heartBeatTimer = null;
  }

  void reconnect() {
    status = SocketStatus.closed;
    if (reconnectTime < maxReconnectTime) {
      reconnectTime++;
      reconnectTimer ??= Timer.periodic(const Duration(seconds: 5), (timer) {
        connect();
      });
    } else {
      onClose?.call('重连超过最大次数，与服务器断开连接');
      reconnectTimer?.cancel();
      reconnectTimer = null;
      close();
      return;
    }
  }
}
