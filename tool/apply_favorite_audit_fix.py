from pathlib import Path
import re


def load(path: str):
    with open(path, "r", encoding="utf-8", newline="") as handle:
        raw = handle.read()
    newline = "\r\n" if "\r\n" in raw else "\n"
    return raw.replace("\r\n", "\n"), newline


def save(path: str, text: str, newline: str):
    with open(path, "w", encoding="utf-8", newline="") as handle:
        handle.write(text.replace("\n", newline))


def regex_once(path: str, pattern: str, replacement: str):
    text, newline = load(path)
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise RuntimeError(f"{path}: expected one match, found {count}")
    save(path, updated, newline)


def replace_once(path: str, old: str, new: str):
    text, newline = load(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected one exact match, found {count}")
    save(path, text.replace(old, new, 1), newline)


regex_once(
    "lib/common/widgets/room_card.dart",
    r"class _FollowButtonState extends State<FollowButton> \{.*?\n\}\n\nclass CountChip",
    """class _FollowButtonState extends State<FollowButton> {
  late bool isFavorite = SettingsService.to.fav.isFavorite(widget.room);

  void _toggleFavorite() {
    final bool wasFavorite = SettingsService.to.fav.isFavorite(widget.room);
    if (wasFavorite) {
      SettingsService.to.fav.removeRoom(widget.room);
    } else {
      SettingsService.to.fav.addRoom(widget.room);
    }

    if (!mounted) return;
    setState(() {
      isFavorite = SettingsService.to.fav.isFavorite(widget.room);
    });
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: _toggleFavorite,
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
      child: Text(
        isFavorite ? i18n("unfollow") : i18n("follow"),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class CountChip""",
)

regex_once(
    "lib/modules/live_play/live_play_page.dart",
    r"class FavoriteFloatingButton extends StatefulWidget \{.*?\n\}\n\nclass NotLivingVideoWidget",
    """class FavoriteFloatingButton extends StatefulWidget {
  const FavoriteFloatingButton({super.key, required this.room});

  final LiveRoom room;

  @override
  State<FavoriteFloatingButton> createState() => _FavoriteFloatingButtonState();
}

class _FavoriteFloatingButtonState extends State<FavoriteFloatingButton> {
  StreamSubscription<dynamic>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = EventBus.instance.listen('changeFavorite', (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }

  void _syncAfterMutation(bool changed) {
    if (mounted) {
      setState(() {});
    }
    if (changed) {
      EventBus.instance.emit('changeFavorite', true);
    }
  }

  Future<void> _unfollow() async {
    final bool? confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: Text(i18n("unfollow")),
        content: Text(
          i18n(
            "unfollow_message",
            args: {"name": widget.room.nick ?? widget.room.title ?? ''},
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(result: false), child: Text(i18n("cancel"))),
          ElevatedButton(onPressed: () => Get.back(result: true), child: Text(i18n("confirm"))),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    _syncAfterMutation(SettingsService.to.fav.removeRoom(widget.room));
  }

  void _follow() {
    _syncAfterMutation(SettingsService.to.fav.addRoom(widget.room));
  }

  @override
  Widget build(BuildContext context) {
    final bool isFavorite = SettingsService.to.fav.isFavorite(widget.room);
    return isFavorite
        ? FilledButton(
            style: ButtonStyle(
              padding: Platform.isWindows
                  ? WidgetStateProperty.all(const EdgeInsets.all(12.0))
                  : WidgetStateProperty.all(const EdgeInsets.all(5.0)),
              backgroundColor: WidgetStateProperty.all(Get.theme.colorScheme.primary.withAlpha(125)),
              shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0))),
              textStyle: WidgetStateProperty.all(AppTextStyles.t12),
              minimumSize: WidgetStateProperty.all(Size.zero),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: _unfollow,
            child: Text(i18n("followed")),
          )
        : FilledButton(
            style: ButtonStyle(
              padding: Platform.isWindows
                  ? WidgetStateProperty.all(const EdgeInsets.all(12.0))
                  : WidgetStateProperty.all(const EdgeInsets.all(5.0)),
              backgroundColor: WidgetStateProperty.all(Get.theme.colorScheme.primary),
              shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0))),
              textStyle: WidgetStateProperty.all(AppTextStyles.t12),
              minimumSize: WidgetStateProperty.all(Size.zero),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: _follow,
            child: Text(i18n("follow")),
          );
  }
}

class NotLivingVideoWidget""",
)

replace_once(
    ".github/workflows/windows-ci.yml",
    "on:\n  workflow_dispatch:\n",
    """on:
  workflow_dispatch:
  push:
    branches:
      - "agent/favorite-audit-fix"
""",
)

for path in (
    ".github/workflows/apply-favorite-audit-fix.yml",
    "tool/apply_favorite_audit_fix.py",
    "tool/run_favorite_audit_fix.py",
):
    Path(path).unlink(missing_ok=True)
