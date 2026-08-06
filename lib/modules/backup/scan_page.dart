import 'package:pure_live/common/index.dart';
import 'package:pure_live/plugins/file_utils.dart';
import 'package:pure_live/plugins/backup_recovery_service.dart';

class ScanCodePage extends StatefulWidget {
  const ScanCodePage({super.key});

  @override
  State<ScanCodePage> createState() => _ScanCodePageState();
}

class _ScanCodePageState extends State<ScanCodePage> {
  final TextEditingController _urlController = TextEditingController();
  bool _syncing = false;
  bool? _syncResult;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _sync() async {
    final url = _urlController.text.trim();
    if (!FileUtils.isHostUrl(url)) {
      ToastUtil.show(i18n('sync_failed'));
      return;
    }

    setState(() {
      _syncing = true;
      _syncResult = null;
    });

    final result = await BackupRecoveryService().pushSettingsToRemoteServer(url);
    if (!mounted) return;

    setState(() {
      _syncing = false;
      _syncResult = result;
    });
    ToastUtil.show(result ? i18n('sync_success') : i18n('sync_failed'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n('scan_qr_code'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _urlController,
                  enabled: !_syncing,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'https://...',
                  ),
                  onSubmitted: (_) => _sync(),
                ),
                const SizedBox(height: 16),
                if (_syncing)
                  Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(i18n('syncing')),
                    ],
                  )
                else
                  FilledButton(
                    onPressed: _sync,
                    child: Text(i18n('tap_to_sync')),
                  ),
                if (_syncResult != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _syncResult! ? i18n('sync_success') : i18n('sync_failed'),
                    style: AppTextStyles.t16.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
