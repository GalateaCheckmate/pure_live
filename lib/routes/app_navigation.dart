import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:pure_live/common/global/platform_utils.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/live_play_controller.dart';
import 'package:pure_live/player/utils/fullscreen.dart';
import 'package:pure_live/plugins/utils.dart';

/// APP页面跳转封装
/// * 需要参数的页面都应使用此类
/// * 如不需要参数，可以使用Get.toNamed
class AppNavigator {
  static bool _openingLiveRoom = false;

  /// 跳转至分类详情
  static void toCategoryDetail({
    required Site site,
    required LiveArea category,
  }) {
    Get.toNamed(RoutePath.kAreaRooms, arguments: [site, category]);
  }

  /// 跳转至直播间。同一次导航未结束时忽略重复点击，避免同时创建两个播放器页面。
  static Future<void> toLiveRoomDetail({required LiveRoom liveRoom}) async {
    if (_openingLiveRoom) return;
    _openingLiveRoom = true;
    try {
      await Get.toNamed(
        RoutePath.kLivePlay,
        arguments: liveRoom,
        parameters: {'site': liveRoom.platform!},
      );
    } finally {
      _openingLiveRoom = false;
    }
  }

  static Future<void> offAndToRoomDetail({
    required LiveRoom liveRoom,
  }) async {
    await Get.offAndToNamed(
      RoutePath.kLivePlay,
      arguments: liveRoom,
      parameters: {'site': liveRoom.platform!},
    );
  }

  /// 跳转至哔哩哔哩登录
  static Future<void> toBiliBiliLogin() async {
    final contents = [i18n('sms_login'), i18n('qrcode_login')];
    if (Platform.isAndroid || Platform.isIOS) {
      final result = await Utils.showOptionDialog(
        contents,
        '',
        title: i18n('select_login_method'),
      );
      if (result == i18n('sms_login')) {
        await Get.toNamed(RoutePath.kBiliBiliWebLogin);
      } else if (result == i18n('qrcode_login')) {
        await Get.toNamed(RoutePath.kBiliBiliQRLogin);
      }
    } else {
      await Get.toNamed(RoutePath.kBiliBiliQRLogin);
    }
  }
}

class BackButtonObserver extends RouteObserver<PageRoute<dynamic>> {
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (route.settings.name != RoutePath.kLivePlay) return;

    try {
      final livePlayController = Get.find<LivePlayController>();
      livePlayController.success.value = false;

      final manager = GlobalPlayerService.instance.playerManager;
      if (SettingsService.to.player.floatPlay.v) {
        Future<void>.delayed(const Duration(milliseconds: 200), () async {
          manager.showAppFloating();
        });
      } else {
        livePlayController.videoController.value?.clearListener();
        if (livePlayController.isCurrentRoomAudioOnly.value) {
          unawaited(manager.hardDispose());
        } else {
          unawaited(manager.close());
        }
      }

      if (PlatformUtils.isMobile) {
        WindowService().doExitFullScreen();
      }
    } catch (error) {
      log('BackButtonObserver Error: $error');
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route.settings.name == RoutePath.kLivePlay) {
      GlobalPlayerService.instance.playerManager.closeAppFloating();
    }
  }
}