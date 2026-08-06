import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/danmaku/bilibili_danmaku.dart';

void main() {
  test('decodes ONLINE_RANK_COUNT from nested zlib packets', () {
    final danmaku = BiliBiliDanmaku();
    int? audienceCount;
    danmaku.onMessage = (message) {
      audienceCount = int.tryParse(message.data?.toString() ?? '');
    };

    final ignoredPacket = _packet(
      utf8.encode(json.encode({'cmd': 'IGNORED_MESSAGE', 'data': {}})),
      protocolVersion: 0,
      operation: 5,
    );
    final audiencePacket = _packet(
      utf8.encode(
        json.encode({
          'cmd': 'ONLINE_RANK_COUNT',
          'data': {
            'count': 99,
            'online_count': 321,
            'online_count_text': '321',
          },
        }),
      ),
      protocolVersion: 0,
      operation: 5,
    );
    final compressedPacket = _packet(
      zlib.encode([...ignoredPacket, ...audiencePacket]),
      protocolVersion: 2,
      operation: 5,
    );

    danmaku.decodeMessage(compressedPacket);

    expect(audienceCount, 321);
  });

  test('uses online_count_text when numeric audience count is absent', () {
    final danmaku = BiliBiliDanmaku();
    int? audienceCount;
    danmaku.onMessage = (message) {
      audienceCount = int.tryParse(message.data?.toString() ?? '');
    };

    final packet = _packet(
      utf8.encode(
        json.encode({
          'cmd': 'ONLINE_RANK_COUNT_V2',
          'data': {'online_count_text': '1.2万'},
        }),
      ),
      protocolVersion: 0,
      operation: 5,
    );

    danmaku.decodeMessage(packet);

    expect(audienceCount, 12000);
  });
}

List<int> _packet(
  List<int> body, {
  required int protocolVersion,
  required int operation,
}) {
  final packet = Uint8List(16 + body.length);
  final header = ByteData.view(packet.buffer);
  header.setUint32(0, packet.length, Endian.big);
  header.setUint16(4, 16, Endian.big);
  header.setUint16(6, protocolVersion, Endian.big);
  header.setUint32(8, operation, Endian.big);
  header.setUint32(12, 1, Endian.big);
  packet.setRange(16, packet.length, body);
  return packet;
}
