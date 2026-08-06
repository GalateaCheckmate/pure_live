import 'package:pure_live/common/index.dart';
import 'package:fullscreen_window/fullscreen_window.dart';
import 'package:pure_live/player/utils/window_helper.dart';
import 'package:pure_live/modules/live_play/player_state.dart';
import 'package:pure_live/modules/live_play/live_play_controller.dart';

class WindowService {
  static final WindowService _instance = WindowService._internal();
  factory WindowService() => _instance;
  WindowService._internal();

  Future<void> enterWinPiP(double videoRatio) async {
    if (GlobalPlayerState.to.isFullscreen.value) {
      final livePlayController = Get.find<LivePlayController>();
      livePlayController.videoController.value?.toggleFullScreen();
    }
    await Future<void>.microtask(() {
      WindowHelper.instance.enterPiP(videoRatio);
    });
  }

  Future<void> exitWinPiP() async {
    WindowHelper.instance.exitPiP();
  }

  Future<void> landScape() => doEnterWindowFullScreen();

  Future<void> verticalScreen() async {
    // Windows has no device-orientation transition.
  }

  Future<void> doEnterFullScreen() => doEnterWindowFullScreen();

  Future<void> doExitFullScreen() => doExitWindowFullScreen();

  Future<void> doExitWindowFullScreen() async {
    FullScreenWindow.setFullScreen(false);
  }

  Future<void> doEnterWindowFullScreen({bool enableEscListener = true, VoidCallback? onEsc}) async {
    FullScreenWindow.setFullScreen(true);
  }
}
