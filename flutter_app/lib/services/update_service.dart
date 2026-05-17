import 'package:dio/dio.dart';
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class UpdateService {
  static const _apiUrl =
      'https://api.github.com/repos/Vijayvsnv/tark-peer/releases/latest';

  /// Returns {version, url} if a newer release exists, null otherwise.
  Future<Map<String, String>?> checkForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final current = info.version;

      final resp = await Dio().get(
        _apiUrl,
        options: Options(headers: {'Accept': 'application/vnd.github+json'}),
      );
      final data = resp.data as Map<String, dynamic>;

      final tag = (data['tag_name'] as String? ?? '').replaceAll('v', '');
      if (tag.isEmpty || !_isNewer(current, tag)) return null;

      final assets = data['assets'] as List<dynamic>? ?? [];
      String? downloadUrl;
      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('.apk')) {
          downloadUrl = asset['browser_download_url'] as String?;
          break;
        }
      }
      if (downloadUrl == null) return null;

      return {'version': tag, 'url': downloadUrl};
    } catch (_) {
      return null;
    }
  }

  /// Downloads the APK and opens the system installer.
  Future<void> downloadAndInstall(
    String url, {
    required void Function(double progress) onProgress,
    required void Function(String error) onError,
    required void Function() onDone,
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/tark_peer_update.apk';

      await Dio().download(
        url,
        path,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress(received / total);
        },
      );

      onDone();
      final result = await OpenFile.open(path);
      if (result.type != ResultType.done) {
        onError('Install karne mein problem: ${result.message}');
      }
    } catch (e) {
      onError('Download fail hua, dobara try karo');
    }
  }

  bool _isNewer(String current, String latest) {
    try {
      List<int> parse(String v) =>
          v.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final c = parse(current);
      final l = parse(latest);
      while (c.length < 3) c.add(0);
      while (l.length < 3) l.add(0);
      for (int i = 0; i < 3; i++) {
        if (l[i] > c[i]) return true;
        if (l[i] < c[i]) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
