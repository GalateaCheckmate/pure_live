import 'dart:async';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/consts/app_consts.dart';
import 'package:pure_live/modules/areas/areas_page.dart';
import 'package:pure_live/modules/home/mobile_view.dart';
import 'package:pure_live/modules/home/tablet_view.dart';
import 'package:pure_live/modules/popular/popular_page.dart';
import 'package:pure_live/modules/favorite/favorite_page.dart';
import 'package:pure_live/modules/about/widgets/version_dialog.dart';
import 'package:pure_live/recorder/pages/recorder/recorder_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with AutomaticKeepAliveClientMixin {
  Timer? _debounceTimer;
  Worker? _tabBottomWorker;
  Worker? _savedMenuWorker;
  final FavoriteController favoriteController = Get.find<FavoriteController>();

  int _selectedIndex = 0;

  final Map<HomeMenu, Widget> _pageMap = const {
    HomeMenu.favorites: FavoritePage(),
    HomeMenu.popular: PopularPage(),
    HomeMenu.areas: AreasPage(),
    HomeMenu.record: RecorderPage(),
  };

  @override
  void initState() {
    super.initState();
    _syncInitialIndex();
    addToOverlay();

    _tabBottomWorker = ever(favoriteController.tabBottomIndex, (index) {
      if (mounted) {
        setState(() => _selectedIndex = index);
      }
    });

    _savedMenuWorker = ever(SettingsService.to.app.savedMenuIds, (value) {
      if (mounted && value.isNotEmpty) {
        final currentMenuId = HomeMenu.values[_selectedIndex].id;
        if (!value.contains(currentMenuId)) {
          final firstMenu = HomeMenu.fromId(value.first);
          if (firstMenu != null) {
            onDestinationSelected(firstMenu.index);
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _tabBottomWorker?.dispose();
    _savedMenuWorker?.dispose();
    super.dispose();
  }

  void _syncInitialIndex() {
    final activeIds = SettingsService.to.app.savedMenuIds.v;
    if (activeIds.isNotEmpty) {
      final firstMenu = HomeMenu.fromId(activeIds.first);
      if (firstMenu != null) {
        _selectedIndex = firstMenu.index;
        favoriteController.tabBottomIndex.value = firstMenu.index;
      }
    }
  }

  void debounceListen(Function? func, [int delay = 1000]) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(Duration(milliseconds: delay), () {
      func?.call();
      _debounceTimer = null;
    });
  }

  void handMoveRefresh() {
    favoriteController.refreshData();
  }

  void onDestinationSelected(int index) {
    if (mounted) {
      setState(() => _selectedIndex = index);
    }
    favoriteController.tabBottomIndex.value = index;
  }

  Future<void> addToOverlay() async {
    final overlay = Overlay.maybeOf(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Container(
        alignment: Alignment.center,
        color: Colors.black54,
        child: NewVersionDialog(entry: entry),
      ),
    );
    await VersionUtil.initPackageInfo();
    await VersionUtil().checkUpdate();
    final hasNewVersion = SettingsService.to.app.enableAutoCheckUpdate.v && VersionUtil.hasNewVersion();
    if (!mounted || overlay == null || !hasNewVersion) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) overlay.insert(entry);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(
      builder: (context, constraint) {
        final bool isTablet = constraint.maxWidth > 680;

        return Obx(() {
          final activeMenuIds = List<String>.from(SettingsService.to.app.savedMenuIds.v);
          if (isTablet) {
            activeMenuIds.remove(HomeMenu.record.id);
          }
          if (activeMenuIds.isEmpty) return const Scaffold();

          int adjustedIndex = _selectedIndex;
          if (adjustedIndex >= HomeMenu.values.length ||
              (isTablet && HomeMenu.values[adjustedIndex] == HomeMenu.record)) {
            final fallbackMenu = HomeMenu.fromId(activeMenuIds.first);
            if (fallbackMenu != null) {
              adjustedIndex = fallbackMenu.index;
            }
          }

          final currentMenu = HomeMenu.values[adjustedIndex];
          final currentWidget = _pageMap[currentMenu] ?? const SizedBox.shrink();

          return !isTablet
              ? HomeMobileView(
                  body: currentWidget,
                  index: adjustedIndex,
                  onDestinationSelected: onDestinationSelected,
                  onFavoriteDoubleTap: handMoveRefresh,
                )
              : HomeTabletView(
                  body: currentWidget,
                  index: adjustedIndex,
                  activeMenuIds: activeMenuIds,
                  onDestinationSelected: onDestinationSelected,
                );
        });
      },
    );
  }

  @override
  bool get wantKeepAlive => true;
}
