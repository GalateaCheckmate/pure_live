import 'package:pure_live/common/index.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/player/utils/player_consts.dart';

enum StreamErrorType {
  roomNotFound,
  notLive,
  noQuality,
  cdnFailed,
  networkError,
  loginExpired,
  banned,
  unknown,
}

class StreamException implements Exception {
  final StreamErrorType type;
  final String message;
  final bool retryable;

  const StreamException({
    required this.type,
    required this.message,
    this.retryable = true,
  });

  @override
  String toString() {
    return 'StreamException(type: $type, message: $message, retryable: $retryable)';
  }
}

class ResolvedStreamSet {
  final List<String> urls;
  final String preferredQuality;

  const ResolvedStreamSet({
    required this.urls,
    required this.preferredQuality,
  });
}

class StreamResolverService extends GetxService {
  static StreamResolverService get to => Get.find();

  Future<String> resolveStream({
    required String roomId,
    required String platform,
    required String preferredQuality,
  }) async {
    final result = await resolveStreamCandidates(
      roomId: roomId,
      platform: platform,
      preferredQuality: preferredQuality,
    );
    return result.urls.first;
  }

  Future<ResolvedStreamSet> resolveStreamCandidates({
    required String roomId,
    required String platform,
    required String preferredQuality,
  }) async {
    try {
      final site = Sites.of(platform).liveSite;
      final detail = await site.getRoomDetail(
        roomId: roomId,
        platform: platform,
      );

      if (detail.liveStatus != LiveStatus.live) {
        throw StreamException(
          type: StreamErrorType.notLive,
          message: i18n('stream_not_live'),
          retryable: false,
        );
      }

      List<LivePlayQuality> qualities;
      try {
        qualities = await site.getPlayQualites(detail: detail);
      } catch (_) {
        throw StreamException(
          type: StreamErrorType.noQuality,
          message: i18n('stream_get_quality_failed'),
          retryable: false,
        );
      }

      if (qualities.isEmpty) {
        throw StreamException(
          type: StreamErrorType.noQuality,
          message: i18n('stream_no_available_quality'),
          retryable: false,
        );
      }

      final systemResolutions = PlayerConsts.resolutions;
      var preferIndex = systemResolutions.indexOf(preferredQuality);
      if (preferIndex == -1) preferIndex = 0;
      final targetRatio =
          preferIndex / (systemResolutions.length - 1).clamp(1, 999);
      final originalIndexMap = <LivePlayQuality, int>{
        for (var index = 0; index < qualities.length; index++)
          qualities[index]: index,
      };
      qualities.sort((a, b) {
        final indexA = originalIndexMap[a]!;
        final indexB = originalIndexMap[b]!;
        final ratioA = indexA / (qualities.length - 1).clamp(1, 999);
        final ratioB = indexB / (qualities.length - 1).clamp(1, 999);
        return (ratioA - targetRatio)
            .abs()
            .compareTo((ratioB - targetRatio).abs());
      });

      final candidates = <String>[];
      final seen = <String>{};
      for (final quality in qualities) {
        try {
          final urls = await site.getPlayUrls(
            detail: detail,
            quality: quality,
          );
          for (final url in urls) {
            final normalized = url.trim();
            if (normalized.isNotEmpty && seen.add(normalized)) {
              candidates.add(normalized);
            }
          }
        } catch (_) {
          continue;
        }
      }

      if (candidates.isEmpty) {
        throw StreamException(
          type: StreamErrorType.cdnFailed,
          message: i18n('stream_all_cdn_failed'),
          retryable: true,
        );
      }

      return ResolvedStreamSet(
        urls: List.unmodifiable(candidates),
        preferredQuality: preferredQuality,
      );
    } on StreamException {
      rethrow;
    } catch (error) {
      throw StreamException(
        type: StreamErrorType.unknown,
        message: error.toString(),
        retryable: true,
      );
    }
  }
}
