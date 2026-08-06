import 'dart:async';
import 'dart:developer' as developer;
import 'package:pure_live/common/index.dart';
import 'package:pure_live/plugins/event_bus.dart';
import 'package:pure_live/modules/tags/live_tag.dart';
import 'package:pure_live/modules/tags/tag_management_controller.dart';
import 'package:pure_live/common/services/settings/refresh_config_controller.dart';

class FavoriteController extends LocalReactivePageController<LiveRoom> with GetTickerProviderStateMixin {
  final TagManagementController tagController = Get.find<TagManagementController>();
  final RefreshConfigController refreshConfigController = Get.find<RefreshConfigController>();

  late TabController tabController;

  final tabBottomIndex = 0.obs;
  final tabSiteIndex = 0.obs;
  final tabOnlineIndex = 0.obs;
  StreamSubscription<dynamic>? subscription;
  StreamSubscription<dynamic>? _configSubscription;
  Timer? _autoRefreshTimer;
  Stopwatch? _refreshStopwatch;
  Timer? _debounceTimer;
  int _refreshGeneration = 0;
  final List<Worker> _workers = <Worker>[];

  final onlineRooms = <LiveRoom>[].obs;
  final offlineRooms = <LiveRoom>[].obs;
  final replayRooms = <LiveRoom>[].obs;
  final selectedTagId = TagManagementController.allTagKey.obs;
  final visibleTags = <LiveTag>[].obs;

  FavoriteController() : super();

  @override
  void onInit() {
    super.onInit();

    tabController = TabController(length: 3, vsync: this);

    _workers.addAll([
      ever(SettingsService.to.fav.favoriteRooms, (_) => applyLocalFilter()),
      ever(tagController.tags, (_) => applyLocalFilter()),
      ever(tagController.roomTagsMap, (_) => applyLocalFilter()),
    ]);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      applyLocalFilter();
    });

    tabController.addListener(() {
      if (tabOnlineIndex.value != tabController.index) {
        tabOnlineIndex.value = tabController.index;
        if (Get.width > 680) {
          currentPage = 1;
        }
        applyLocalFilter();
      }
    });

    _setupRefreshStrategy();
    _configSubscription = refreshConfigController.configChanges.listen((config) {
      _setupRefreshStrategy();
    });

    listenFavorite();
  }

  void _setupRefreshStrategy() {
    _autoRefreshTimer?.cancel();
    final bool isEnabled = refreshConfigController.autoRefreshFavorite.value;
    final int interval = refreshConfigController.autoRefreshInterval.value;
    if (isEnabled && interval > 0) {
      _autoRefreshTimer = Timer.periodic(Duration(minutes: interval), (timer) => refreshData());
    }
  }

  void debounceRefresh() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _fullRefreshRooms();
    });
  }

  @override
  void onClose() {
    _refreshGeneration++;
    for (final worker in _workers) {
      worker.dispose();
    }
    _workers.clear();
    tabController.dispose();
    subscription?.cancel();
    _configSubscription?.cancel();
    _autoRefreshTimer?.cancel();
    _debounceTimer?.cancel();
    super.onClose();
  }

  void listenFavorite() {
    subscription = EventBus.instance.listen('refresh_favorite_rooms', (data) {
      debounceRefresh();
    });
  }

  void changeSelectedTag(String tagId) {
    if (selectedTagId.value == tagId) return;
    selectedTagId.value = tagId;
    if (Get.width > 680) {
      currentPage = 1;
    }
    applyLocalFilter();
  }

  void changeSite(int siteIndex) {
    final availableSites = Sites().availableSites(containsAll: true);
    if (siteIndex < 0 || siteIndex >= availableSites.length) return;

    final bool siteChanged = tabSiteIndex.value != siteIndex;
    final bool tagChanged = selectedTagId.value != TagManagementController.allTagKey;
    if (!siteChanged && !tagChanged) return;

    selectedTagId.value = TagManagementController.allTagKey;
    tabSiteIndex.value = siteIndex;
    if (Get.width > 680) {
      currentPage = 1;
    }
    applyLocalFilter();
  }

  void updateRoomTags(LiveRoom room, List<String> newTagIds) {
    tagController.setRoomTags(room, newTagIds);
  }

  List<LiveRoom> getAllRooms() {
    return List<LiveRoom>.from(SettingsService.to.fav.favoriteRooms.v);
  }

  List<LiveRoom> getFilteredRoomsIgnoringLiveStatus() {
    final List<LiveRoom> source = List<LiveRoom>.from(SettingsService.to.fav.favoriteRooms.v);

    final currentAvailableSites = Sites().availableSites(containsAll: true);
    if (tabSiteIndex.value < 0 || tabSiteIndex.value >= currentAvailableSites.length) {
      return [];
    }

    final activeSite = currentAvailableSites[tabSiteIndex.value];
    List<LiveRoom> siteFiltered = source;

    if (activeSite.id != Sites.allSite) {
      siteFiltered = source.where((room) {
        return room.platform?.toUpperCase() == activeSite.id.toUpperCase();
      }).toList();
    }

    if (selectedTagId.value == TagManagementController.allTagKey) {
      return siteFiltered;
    }

    return siteFiltered.where((room) {
      final List<String> ids = tagController.getTagsForRoom(room);
      return ids.contains(selectedTagId.value);
    }).toList();
  }

  List<LiveRoom> getFilteredRooms() {
    syncRooms();

    List<LiveRoom> source;

    switch (tabOnlineIndex.value) {
      case 0:
        source = onlineRooms;
        break;
      case 1:
        source = replayRooms;
        break;
      case 2:
        source = offlineRooms;
        break;
      default:
        source = onlineRooms;
    }

    final currentAvailableSites = Sites().availableSites(containsAll: true);
    if (tabSiteIndex.value < 0 || tabSiteIndex.value >= currentAvailableSites.length) {
      return [];
    }

    final activeSite = currentAvailableSites[tabSiteIndex.value];
    List<LiveRoom> siteFiltered = source;

    if (activeSite.id != Sites.allSite) {
      siteFiltered = source.where((room) {
        return room.platform?.toUpperCase() == activeSite.id.toUpperCase();
      }).toList();
    }

    if (selectedTagId.value == TagManagementController.allTagKey) {
      return siteFiltered;
    }

    return siteFiltered.where((room) {
      final List<String> ids = tagController.getTagsForRoom(room);
      return ids.contains(selectedTagId.value);
    }).toList();
  }

  void syncRooms() {
    onlineRooms.clear();
    replayRooms.clear();
    offlineRooms.clear();

    final List<LiveRoom> roomsBase = List<LiveRoom>.from(SettingsService.to.fav.favoriteRooms.v);
    onlineRooms.addAll(roomsBase.where((r) => r.liveStatus == LiveStatus.live && r.isRecord == false));
    offlineRooms.addAll(roomsBase.where((r) => r.liveStatus != LiveStatus.live));
    replayRooms.addAll(roomsBase.where((r) => r.liveStatus == LiveStatus.live && r.isRecord == true));

    final currentAvailableSites = Sites().availableSites(containsAll: true);
    visibleTags.clear();

    if (tabSiteIndex.value >= 0 && tabSiteIndex.value < currentAvailableSites.length) {
      final activeSite = currentAvailableSites[tabSiteIndex.value];
      List<LiveRoom> target;

      switch (tabOnlineIndex.value) {
        case 0:
          target = onlineRooms;
          break;
        case 1:
          target = replayRooms;
          break;
        case 2:
          target = offlineRooms;
          break;
        default:
          target = onlineRooms;
      }

      final Set<String> tagIds = {};
      for (var room in target) {
        if (activeSite.id == Sites.allSite || room.platform?.toUpperCase() == activeSite.id.toUpperCase()) {
          tagIds.addAll(tagController.getTagsForRoom(room));
        }
      }

      final tags = tagController.tags.where((t) => tagIds.contains(t.id)).toList();
      tags.sort((a, b) => a.order.compareTo(b.order));
      visibleTags.assignAll(tags);
    }

    for (var room in onlineRooms) {
      room.watching = int.tryParse(room.watching ?? '')?.toString() ?? '0';
    }
    for (var room in replayRooms) {
      room.watching = int.tryParse(room.watching ?? '')?.toString() ?? '0';
    }

    onlineRooms.sort(_compareRooms);
    replayRooms.sort(_compareRooms);
  }

  int _compareRooms(LiveRoom a, LiveRoom b) {
    if (selectedTagId.value == TagManagementController.allTagKey) {
      return int.parse(b.watching!).compareTo(int.parse(a.watching!));
    }
    final int sa = _getRoomTagScore(a);
    final int sb = _getRoomTagScore(b);
    if (sa != sb) return sb.compareTo(sa);
    return int.parse(b.watching!).compareTo(int.parse(a.watching!));
  }

  int _getRoomTagScore(LiveRoom room) {
    final ids = tagController.getTagsForRoom(room);
    if (ids.isEmpty) return 0;

    int highest = 0;
    const maxScore = 1000000;

    for (var id in ids) {
      final idx = tagController.tags.indexWhere((t) => id == t.id);
      if (idx != -1) {
        final tag = tagController.tags[idx];
        final score = maxScore - tag.order * 100;
        if (score > highest) highest = score;
      }
    }
    return highest;
  }

  void applyLocalFilter() {
    final filtered = getFilteredRooms();
    updateLocalReactivePool(filtered);
  }

  @override
  Future<void> refreshData() async {
    currentPage = 1;
    await _fullRefreshFilterRooms();
  }

  Future<void> _fullRefreshFilterRooms() async {
    final int generation = ++_refreshGeneration;
    loadding.value = true;
    try {
      final roomsToRefresh = getFilteredRoomsIgnoringLiveStatus();
      final applied = await _refreshRoomDetails(roomsToRefresh, generation);
      if (applied && generation == _refreshGeneration) {
        EventBus.instance.emit('refresh_favorite_finish', true);
      }
    } finally {
      if (generation == _refreshGeneration) {
        loadding.value = false;
      }
    }
  }

  Future<void> _fullRefreshRooms() async {
    final int generation = ++_refreshGeneration;
    loadding.value = true;
    try {
      final roomsToRefresh = getAllRooms();
      final applied = await _refreshRoomDetails(roomsToRefresh, generation);
      if (applied && generation == _refreshGeneration) {
        EventBus.instance.emit('refresh_favorite_finish', true);
      }
    } finally {
      if (generation == _refreshGeneration) {
        loadding.value = false;
      }
    }
  }

  Future<bool> _refreshRoomDetails(List<LiveRoom> rooms, int generation) async {
    final valid = rooms.where((room) {
      return room.roomId != null && (room.platform?.isNotEmpty ?? false);
    }).toList(growable: false);

    if (valid.isEmpty) return true;

    _refreshStopwatch = Stopwatch()..start();

    try {
      // Start every room request immediately. Each request handles its own
      // failure so one slow or broken platform cannot cancel the whole refresh.
      final results = await Future.wait<LiveRoom?>(
        valid.map((room) async {
          try {
            return await Sites.of(room.platform!)
                .liveSite
                .getRoomDetail(roomId: room.roomId!, platform: room.platform!)
                .timeout(const Duration(seconds: 20));
          } catch (error, stackTrace) {
            developer.log(
              'Failed to refresh ${room.platform}:${room.roomId}: $error',
              name: 'FavoriteController',
              stackTrace: stackTrace,
            );
            return null;
          }
        }),
      );

      if (generation != _refreshGeneration) {
        return false;
      }

      final Map<String, LiveRoom> refreshedByKey = {};
      for (final updated in results) {
        if (updated == null || updated.roomId == null || updated.platform == null) continue;
        refreshedByKey[_roomKey(updated)] = updated;
      }

      if (refreshedByKey.isEmpty) {
        return true;
      }

      // Merge into the latest list so favorites added or removed while the
      // network requests were running are preserved. Publish only once so the
      // UI keeps the original all-at-once refresh behavior.
      final current = List<LiveRoom>.from(SettingsService.to.fav.favoriteRooms.v);
      final merged = current.map((room) => refreshedByKey[_roomKey(room)] ?? room).toList(growable: false);
      SettingsService.to.fav.favoriteRooms.v = merged;
      return true;
    } finally {
      _refreshStopwatch?.stop();
      _refreshStopwatch = null;
    }
  }

  String _roomKey(LiveRoom room) {
    return '${room.platform?.toUpperCase() ?? ''}:${room.roomId ?? ''}';
  }
}
