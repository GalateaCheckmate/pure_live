import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

class FileUtils {
  static const String systemHotProviderId = '88888';

  static String getFileName(String fullPath) {
    return fullPath.split(Platform.pathSeparator).last;
  }

  static String getBaseName(String fullPath) {
    return p.basenameWithoutExtension(fullPath);
  }

  static String generateUuid() {
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    final randomValue = Random().nextInt(4294967295);
    final result = (currentTime % 10000000000 * 1000 + randomValue) % 4294967295;
    return result.toString();
  }

  static bool isValidUrl(String value) {
    final urlRegExp = RegExp(
      r"((https?:www\.)|(https?:\/\/)|(www\.))[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9]{1,6}(\/[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)?",
    );
    return urlRegExp.allMatches(value).isNotEmpty;
  }

  static bool isHostUrl(String value) {
    final urlRegExp = RegExp(
      r"((https?:www\.)|(https?:\/\/))[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9]{1,6}(\/[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)?",
    );
    return urlRegExp.allMatches(value).isNotEmpty;
  }

  static bool isNumericPort(String value) {
    return RegExp(r'^\d+$').hasMatch(value);
  }

  static Future<bool> requestStoragePermission() async => true;

  static Future<File> convertPhysicalFile(String shareContent) async {
    if (shareContent.isEmpty) {
      throw const FileSystemException('Shared data string content stream is fully empty');
    }
    if (shareContent.startsWith('file://')) {
      return File(Uri.parse(shareContent).toFilePath());
    }

    final fileRef = File(shareContent);
    if (await fileRef.exists()) {
      return fileRef;
    }
    throw FileSystemException(
      'Shared media target path cannot be verified on local storage',
      shareContent,
    );
  }

  static Future<bool> openFileOrUrl(String pathOrUrl) async {
    final trimmedPath = pathOrUrl.trim();
    if (trimmedPath.isEmpty) return false;

    if (isValidUrl(trimmedPath)) {
      try {
        final uri = Uri.parse(trimmedPath);
        if (await canLaunchUrl(uri)) {
          return launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } catch (_) {
        return false;
      }
      return false;
    }

    final file = File(trimmedPath);
    final directory = Directory(trimmedPath);
    if (!await file.exists() && !await directory.exists()) return false;

    try {
      await Process.run('explorer.exe', [p.context.canonicalize(trimmedPath)]);
      return true;
    } catch (_) {
      try {
        final result = await OpenFilex.open(trimmedPath);
        return result.type == ResultType.done;
      } catch (_) {
        return false;
      }
    }
  }
}
