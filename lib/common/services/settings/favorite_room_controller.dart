import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/consts/app_consts.dart';
import 'package:pure_live/common/services/utils/backup_migration_util.dart';

class FavoriteRoomController extends GetxController {
  final RxList<String> shieldList = hiveStringList('shieldList', []);
  final RxList<String> hotAreasList = hiveStringList('hotAreasList', AppConsts.supportSites);
  final RxString preferPlatform = hiveString('preferPlatform', Sites.bilibiliSite);
  final Rx<List<LiveRoom>> favoriteRooms = hiveObject(
    'favoriteRooms',
    <LiveRoom>[],
    fromJson: (json) {
      return List<LiveRoom>.from((json['list'] ?? []).map((e) => LiveRoom.fromJson(e)));
    },
    toJson: (list) {
      return {'list': list.map((e) => e.toJson()).toList()};
    },
  );

  bool _isSameRoom(LiveRoom first, LiveRoom second) {
    return first.roomId == second.roomId &&
        first.platform?.toUpperCase() == second.platform?.toUpperCase();
  }

  bool isFavorite(LiveRoom room) => favoriteRooms.v.any((e) => _isSameRoom(e, room));
  bool isFavoriteArea(LiveArea area) => favoriteAreas.v.any((e) => e.areaId == area.areaId);

  bool addRoom(LiveRoom room) {
    if (isFavorite(room)) return false;
    favoriteRooms.v.add(room);
    favoriteRooms.refresh();
    return true;
  }

  bool removeRoom(LiveRoom room) {
    final idx = favoriteRooms.v.indexWhere((e) => _isSameRoom(e, room));
    if (idx == -1) return false;
    favoriteRooms.v.removeAt(idx);
    favoriteRooms.refresh();
    return true;
  }

  bool updateRoom(LiveRoom room) {
    final idx = favoriteRooms.v.indexWhere((e) => _isSameRoom(e, room));
    if (idx == -1) return false;
    favoriteRooms.v[idx] = room;
    favoriteRooms.refresh();
    return true;
  }

  bool addArea(LiveArea area) {
    if (isFavoriteArea(area)) return false;
    favoriteAreas.v.add(area);
    favoriteAreas.refresh();
    return true;
  }

  bool removeArea(LiveArea area) {
    final res = favoriteAreas.v.remove(area);
    favoriteAreas.refresh();
    return res;
  }

  void addShieldList(String value) => shieldList.v.add(value);
  void removeShieldList(int idx) => shieldList.v.removeAt(idx);

  LiveRoom? getRoomById(String roomId, String platform) {
    for (final room in favoriteRooms.v) {
      if (room.roomId == roomId && room.platform?.toUpperCase() == platform.toUpperCase()) {
        return room;
      }
    }
    return null;
  }

  void changePreferPlatform(String name) {
    final list = Sites.supportSites.map((e) => e.id).toList();
    if (list.contains(name)) {
      preferPlatform.v = name;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'shieldList': shieldList.v,
      'hotAreasList': hotAreasList.v,
      'preferPlatform': preferPlatform.v,
      'favoriteRooms': favoriteRooms.v.map((e) => e.toJson()).toList(),
      'favoriteAreas': favoriteAreas.v.map((e) => e.toJson()).toList(),
    };
  }

  void fromJson(Map<String, dynamic> json) {
    shieldList.v = List<String>.from(json['shieldList'] ?? []);

    hotAreasList.v = List<String>.from(json['hotAreasList'] ?? AppConsts.supportSites);

    preferPlatform.v = json['preferPlatform'] ?? Sites.bilibiliSite;

    favoriteRooms.v = BackupMigrationUtil.parseObjectList(json['favoriteRooms'], (m) => LiveRoom.fromJson(m));

    favoriteAreas.v = BackupMigrationUtil.parseObjectList(json['favoriteAreas'], (m) => LiveArea.fromJson(m));
  }

  static Map<String, dynamic> extractConfig(Map<String, dynamic>? rootConfig) {
    final favorite = rootConfig?['favorite'] as Map<String, dynamic>? ?? {};
    return {
      'shieldList': List<String>.from(favorite['shieldList'] ?? []),
      'hotAreasList': List<String>.from(favorite['hotAreasList'] ?? AppConsts.supportSites),
      'preferPlatform': favorite['preferPlatform'] ?? Sites.bilibiliSite,
      'favoriteRooms': BackupMigrationUtil.parseObjectList(
        favorite['favoriteRooms'],
        LiveRoom.fromJson,
      ).map((e) => e.toJson()).toList(),
      'favoriteAreas': BackupMigrationUtil.parseObjectList(
        favorite['favoriteAreas'],
        LiveArea.fromJson,
      ).map((e) => e.toJson()).toList(),
    };
  }

  static Map<String, dynamic> mergeConfig(Map<String, dynamic> rootConfig, Map<String, dynamic> updateFields) {
    final favorite = Map<String, dynamic>.from(rootConfig['favorite'] ?? {});
    updateFields.forEach((k, v) => favorite[k] = v);
    rootConfig['favorite'] = favorite;
    return rootConfig;
  }
}
