import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/favorite/room_grid_view.dart';
import 'package:pure_live/common/widgets/common_appbar_actions.dart';

class FavoritePage extends GetView<FavoriteController> {
  const FavoritePage({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraint) {
        return Obx(() {
          final bool showAction = Get.width <= 680;
          final int menuCount = SettingsService.to.app.savedMenuIds.v.length;
          final List<Site> availableSitesList = Sites().availableSites(containsAll: true);

          return Scaffold(
            appBar: AppBar(
              centerTitle: true,
              leading: (showAction || menuCount <= 1) ? const MenuButton() : null,
              actions: showAction ? [CommonAppBarActions()] : null,
              title: TabBar(
                controller: controller.tabController,
                isScrollable: true,
                tabs: [
                  Tab(text: i18n("online_room_title")),
                  Tab(text: i18n("recording_room_title")),
                  Tab(text: i18n("offline_room_title")),
                ],
              ),
            ),
            body: _FavoriteSiteTabs(
              controller: controller,
              availableSitesList: availableSitesList,
            ),
          );
        });
      },
    );
  }
}

class _FavoriteSiteTabs extends StatefulWidget {
  const _FavoriteSiteTabs({required this.controller, required this.availableSitesList});

  final FavoriteController controller;
  final List<Site> availableSitesList;

  @override
  State<_FavoriteSiteTabs> createState() => _FavoriteSiteTabsState();
}

class _FavoriteSiteTabsState extends State<_FavoriteSiteTabs> with SingleTickerProviderStateMixin {
  late TabController _siteTabController;

  @override
  void initState() {
    super.initState();
    _createSiteTabController();
  }

  @override
  void didUpdateWidget(covariant _FavoriteSiteTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String oldSiteIds = oldWidget.availableSitesList.map((site) => site.id).join('|');
    final String newSiteIds = widget.availableSitesList.map((site) => site.id).join('|');
    if (oldSiteIds != newSiteIds) {
      _siteTabController.removeListener(_handleSiteTabChanged);
      _siteTabController.dispose();
      _createSiteTabController();
    }
  }

  void _createSiteTabController() {
    final int selectedIndex = widget.controller.tabSiteIndex.value;
    final int initialIndex = selectedIndex >= 0 && selectedIndex < widget.availableSitesList.length ? selectedIndex : 0;
    _siteTabController = TabController(
      length: widget.availableSitesList.length,
      initialIndex: initialIndex,
      vsync: this,
    );
    _siteTabController.addListener(_handleSiteTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.controller.changeSite(_siteTabController.index);
      }
    });
  }

  void _handleSiteTabChanged() {
    if (_siteTabController.indexIsChanging) return;
    widget.controller.changeSite(_siteTabController.index);
  }

  @override
  void dispose() {
    _siteTabController.removeListener(_handleSiteTabChanged);
    _siteTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _siteTabController,
          isScrollable: true,
          tabs: widget.availableSitesList.map((site) => Tab(text: site.name)).toList(),
        ),
        Expanded(
          child: BasePageView<FavoriteController, LiveRoom>(
            controller: widget.controller,
            enableRefresh: true,
            enableLoadMore: true,
            emptyBuilder: (context) => AppStatusView(
              type: AppStatusType.empty,
              icon: Remix.heart_3_fill,
              title: i18n("empty_favorite_online_title"),
              subtitle: i18n("empty_favorite_online_subtitle"),
            ),
            showScrollToTopBtn: SettingsService.to.page.showScrollToTopBtn.v,
            showPageSizeSelector: SettingsService.to.page.showPageSizeSelector.v,
            pageSizeOptions: SettingsService.to.page.pageSizeOptions,
            contentBuilder: (context, list, scrollController) {
              return TabBarView(
                controller: _siteTabController,
                children: widget.availableSitesList.map((site) {
                  return RoomGridView(
                    site: site.id,
                    isOnline: widget.controller.tabOnlineIndex.value != 1,
                    scrollController: scrollController,
                    displayList: list,
                  );
                }).toList(),
              );
            },
          ),
        ),
      ],
    );
  }
}
