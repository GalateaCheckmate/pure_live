import 'dart:async';

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
  static bool _requiredServicesInitialized = false;
  static bool _deferredServicesScheduled = false;

  static void initGlobalServices() {
    Get.put(SettingsService(), permanent: true);
    Get.put(RouteObserverController(), permanent: true);
  }

  static void initLazyControllers() {
    Get.lazyPut(() => FavoriteController(), fenix: true);
    Get.lazyPut(() => ChannelDetailController(), fenix: true);
    Get.lazyPut(() => PopularController(), fenix: true);
    Get.lazyPut(() => AreasController(), fenix: true);
    Get.lazyPut(() => GlobalPlayerState(), fenix: true);
  }

  static Future<void> initDb() async {
    final db = DbService();
    await db.init();
    Get.put<DbService>(db, permanent: true);
  }

  /// Initializes services that must exist before [runApp] renders the first
  /// frame. This method is idempotent so repeated calls do not register
  /// duplicate GetX services.
  static Future<void> initRequiredServices() async {
    if (_requiredServicesInitialized) return;

    await initDb();
    initGlobalServices();
    initLazyControllers();
    _requiredServicesInitialized = true;
  }

  /// Starts services that are useful after launch but are not required for the
  /// first frame. Scheduling is idempotent to prevent duplicate FFmpeg,
  /// recorder and account controllers.
  static void scheduleDeferredServices() {
    if (_deferredServicesScheduled) return;
    _deferredServicesScheduled = true;

    Timer(const Duration(seconds: 3), () {
      try {
        FFmpegKitExtended.initialize();
        Get.put(CacheService(), permanent: true);
        Get.put(RecordSettingsController(), permanent: true);
        Get.put(RecorderController(), permanent: true);
        Get.lazyPut(() => StreamResolverService(), fenix: true);
        Get.put(AuthController(), permanent: true);
      } catch (error, stackTrace) {
        debugPrint('Deferred service initialization failed: $error\n$stackTrace');
      }
    });
  }

  /// Compatibility entry point for callers outside the startup path.
  static Future<void> init() async {
    await initRequiredServices();
    scheduleDeferredServices();
  }
}
