import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  static const _apiUrl =
      'https://api.github.com/repos/Vijayvsnv/tark-peer/releases/latest';

  Future<Map<String, String>?> checkForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final current = info.version;

      final resp = await http.get(
        Uri.parse(_apiUrl),
        headers: {'Accept': 'application/vnd.github+json'},
      );
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
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

  Future<void> openDownloadUrl(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
