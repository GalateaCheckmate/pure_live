import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:brotli/brotli.dart';
import '../common/binary_writer.dart';
import 'package:pure_live/core/common/core_log.dart';
import 'package:pure_live/common/models/live_message.dart';
import 'package:pure_live/core/common/convert_helper.dart';
import 'package:pure_live/core/common/web_socket_util.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';

class BiliBiliDanmakuArgs {
  final int roomId;
  final String token;
  final String buvid;
  final String serverHost;
  final int uid;
  final String cookie;
  BiliBiliDanmakuArgs({
    required this.roomId,
    required this.token,
    required this.serverHost,
    required this.buvid,
    required this.uid,
    required this.cookie,
  });
  @override
  String toString() {
    return json.encode({
      "roomId": roomId,
      "token": token,
      "serverHost": serverHost,
      "buvid": buvid,
      "uid": uid,
      "cookie": cookie,
    });
  }
}

class BiliBiliDanmaku implements LiveDanmaku {
  @override
  int heartbeatTime = 60 * 1000;
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  void markConnected() {
    _connected = true;
  }

  @override
  void markDisconnected() {
    _connected = false;
  }

  @override
  Function(LiveMessage msg)? onMessage;
  @override
  Function(String msg)? onClose;
  @override
  Function()? onReady;

  WebScoketUtils? webScoketUtils;
  late BiliBiliDanmakuArgs danmakuArgs;
  @override
  Future start(dynamic args) async {
    danmakuArgs = args as BiliBiliDanmakuArgs;
    webScoketUtils = WebScoketUtils(
      url: "wss://${args.serverHost}/sub",
      headers: args.cookie.isEmpty ? null : {"cookie": args.cookie},
      heartBeatTime: heartbeatTime,
      onMessage: (e) {
        decodeMessage(e);
      },
      onReady: () {
        onReady?.call();
        markConnected();
        joinRoom(danmakuArgs);
      },
      onHeartBeat: () {
        heartbeat();
      },
      onReconnect: () {
        markDisconnected();
        onClose?.call("与服务器断开连接，正在尝试重连");
      },
      onClose: (e) {
        markDisconnected();
        onClose?.call("服务器连接失败$e");
      },
    );
    webScoketUtils?.connect();
  }

  void joinRoom(BiliBiliDanmakuArgs args) {
    var joinData = encodeData(
      json.encode({
        "uid": args.uid,
        "roomid": args.roomId,
        "protover": 3,
        "buvid": args.buvid,
        "platform": "web",
        "type": 2,
        "key": args.token,
      }),
      7,
    );
    webScoketUtils?.sendMessage(joinData);
  }

  @override
  void heartbeat() {
    webScoketUtils?.sendMessage(encodeData("", 2));
  }

  @override
  Future stop() async {
    onMessage = null;
    onClose = null;
    webScoketUtils?.close();
    markDisconnected();
  }

  List<int> encodeData(String msg, int action) {
    var data = utf8.encode(msg);
    // 头部长度固定 16。
    var length = data.length + 16;
    var buffer = Uint8List(length);

    var writer = BinaryWriter([]);
    writer.writeInt(buffer.length, 4);
    writer.writeInt(16, 2);
    writer.writeInt(0, 2);
    writer.writeInt(action, 4);
    writer.writeInt(1, 4);
    writer.writeBytes(data);

    return writer.buffer;
  }

  void decodeMessage(List<int> data) {
    try {
      // 心跳回应中的 Int32 是旧的人气值，不再作为房间观众数上报。
      int protocolVersion = readInt(data, 6, 2);
      int operation = readInt(data, 8, 4);
      var body = data.skip(16).toList();

      if (operation == 5) {
        if (protocolVersion == 2) {
          body = zlib.decode(body);
        } else if (protocolVersion == 3) {
          body = brotli.decode(body);
        }

        var text = utf8.decode(body, allowMalformed: true);
        var group = text.split(
          RegExp(r"[\x00-\x1f]+", unicode: true, multiLine: true),
        );
        for (var item in group.where((x) => x.length > 2 && x.startsWith('{'))) {
          parseMessage(item);
        }
      }
    } catch (e) {
      CoreLog.error(e);
    }
  }

  void parseMessage(String jsonMessage) {
    try {
      var obj = json.decode(jsonMessage);
      var cmd = obj["cmd"].toString();
      if (cmd.contains("DANMU_MSG")) {
        if (obj["info"] != null && obj["info"].length != 0) {
          var message = obj["info"][1].toString();
          var color = asT<int?>(obj["info"][0][3]) ?? 0;
          if (obj["info"][2] != null && obj["info"][2].length != 0) {
            var username = obj["info"][2][1].toString();
            var liveMsg = LiveMessage(
              type: LiveMessageType.chat,
              userName: username,
              message: message,
              color: color == 0
                  ? LiveMessageColor.white
                  : LiveMessageColor.numberToColor(color),
            );
            onMessage?.call(liveMsg);
          }
        }
      } else if (cmd.startsWith("ONLINE_RANK_COUNT")) {
        final audienceCount = _readAudienceCount(obj["data"]);
        if (audienceCount != null) {
          onMessage?.call(
            LiveMessage(
              type: LiveMessageType.online,
              data: audienceCount,
              color: LiveMessageColor.white,
              message: "",
              userName: "",
            ),
          );
        }
      } else if (cmd == "SUPER_CHAT_MESSAGE") {
        if (obj["data"] == null) {
          return;
        }
        LiveSuperChatMessage sc = LiveSuperChatMessage(
          backgroundBottomColor: obj["data"]["background_bottom_color"].toString(),
          backgroundColor: obj["data"]["background_color"].toString(),
          endTime: DateTime.fromMillisecondsSinceEpoch(
            obj["data"]["end_time"] * 1000,
          ),
          face: "${obj["data"]["user_info"]["face"]}@200w.jpg",
          message: obj["data"]["message"].toString(),
          price: obj["data"]["price"],
          startTime: DateTime.fromMillisecondsSinceEpoch(
            obj["data"]["start_time"] * 1000,
          ),
          userName: obj["data"]["user_info"]["uname"].toString(),
        );
        var liveMsg = LiveMessage(
          type: LiveMessageType.superChat,
          userName: "SUPER_CHAT_MESSAGE",
          message: "SUPER_CHAT_MESSAGE",
          color: LiveMessageColor.white,
          data: sc,
        );
        onMessage?.call(liveMsg);
      }
    } catch (e) {
      CoreLog.error(e);
    }
  }

  int? _readAudienceCount(dynamic rawData) {
    if (rawData is! Map) return null;

    final rawCount = rawData["online_count"] ?? rawData["onlineCount"];
    if (rawCount is num) return rawCount.toInt();
    if (rawCount != null) {
      final parsed = int.tryParse(rawCount.toString());
      if (parsed != null) return parsed;
    }

    final text = rawData["online_count_text"]?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return _parseReadableCount(text);
  }

  int? _parseReadableCount(String text) {
    final match = RegExp(r"([0-9]+(?:\.[0-9]+)?)").firstMatch(text);
    if (match == null) return null;

    final value = double.tryParse(match.group(1)!);
    if (value == null) return null;
    if (text.contains("亿")) return (value * 100000000).round();
    if (text.contains("万")) return (value * 10000).round();
    return value.round();
  }

  int readInt(List<int> buffer, int start, int len) {
    var bytes = Uint8List.fromList(
      buffer.getRange(start, start + len).toList(),
    );
    var byteBuffer = bytes.buffer;
    var data = ByteData.view(byteBuffer);
    var result = 0;

    if (len == 1) {
      result = data.getUint8(0);
    }
    if (len == 2) {
      result = data.getInt16(0, Endian.big);
    }
    if (len == 4) {
      result = data.getInt32(0, Endian.big);
    }
    if (len == 8) {
      result = data.getInt64(0, Endian.big);
    }

    return result;
  }
}
