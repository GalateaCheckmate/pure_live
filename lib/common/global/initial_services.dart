import 'package:pure_live/common/index.dart';
import 'package:pure_live/plugins/db_service.dart';
import 'package:pure_live/modules/auth/auth_controller.dart';
import 'package:pure_live/modules/live_play/player_state.dart';
import 'package:pure_live/recorder/services/cache_service.dart';
import 'package:pure_live/routes/route_observer_controller.dart';
import 'package:pure_live/recorder/services/stream_resolver_service.dart';
import 'package:pure_live/recorder/pages/recorder/recorder_controller.dart';
import 'package:pure_live/core/iptv/services/channel_detail_controller.dart';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:pure_live/recorder/pages/record_settings/record_settings_controller.dart';

class InitialServices {
  static void initGlobalServices() {
    if (!Get.isRegistered<SettingsService>()) {
      Get.put(SettingsService(), permanent: true);
    }
    if (!Get.isRegistered<RouteObserverController>()) {
      Get.put(RouteObserverController(), permanent: true);
    }
  }

  static void initLazyControllers() {
    if (!Get.isRegistered<FavoriteController>()) {
      Get.lazyPut(() => FavoriteController(), fenix: true);
    }
    if (!Get.isRegistered<ChannelDetailController>()) {
      Get.lazyPut(() => ChannelDetailController(), fenix: true);
    }
    if (!Get.isRegistered<PopularController>()) {
      Get.lazyPut(() => PopularController(), fenix: true);
    }
    if (!Get.isRegistered<AreasController>()) {
      Get.lazyPut(() => AreasController(), fenix: true);
    }
    if (!Get.isRegistered<GlobalPlayerState>()) {
      Get.lazyPut(() => GlobalPlayerState(), fenix: true);
    }
  }

  static Future<void> initDb() async {
    if (Get.isRegistered<DbService>()) return;
    final db = DbService();
    await db.init();
    Get.put<DbService>(db, permanent: true);
  }

  static void initRecorderServices() {
    FFmpegKitExtended.initialize();

    if (!Get.isRegistered<CacheService>()) {
      Get.put(CacheService(), permanent: true);
    }
    if (!Get.isRegistered<RecordSettingsController>()) {
      Get.put(RecordSettingsController(), permanent: true);
    }
    if (!Get.isRegistered<StreamResolverService>()) {
      Get.lazyPut(() => StreamResolverService(), fenix: true);
    }
    if (!Get.isRegistered<RecorderController>()) {
      Get.put(RecorderController(), permanent: true);
    }
  }

  static Future<void> init() async {
    await initDb();
    initGlobalServices();
    initLazyControllers();
    initRecorderServices();
    _initOptionalServices();
  }

  static void _initOptionalServices() {
    // Auth does not block the local player. Initialize it asynchronously, but
    // do not hide registration errors behind a fixed three-second delay.
    Future.microtask(() {
      try {
        if (!Get.isRegistered<AuthController>()) {
          Get.put(AuthController(), permanent: true);
        }
      } catch (e, stackTrace) {
        debugPrint('AuthController initialization failed: $e\n$stackTrace');
      }
    });
  }
}
