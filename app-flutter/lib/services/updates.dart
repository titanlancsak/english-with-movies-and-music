import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../core/app_version.dart';
import 'paths.dart';

/// Looks for a newer version on GitHub when the app opens and offers the download.
class UpdateChecker extends ChangeNotifier {
  static final _api = Uri.parse('https://api.github.com/repos/titanlancsak/english-with-movies-and-music/releases/latest');

  /// e.g. ("v1.3.0", page) when a newer version exists.
  (String tag, Uri page)? available;

  File get _dismissedFile => AppPaths.file(AppPaths.root, 'dismissed-update.txt');

  String get availableVersion => available?.$1.replaceFirst(RegExp('^[vV]'), '') ?? '';

  Future<void> check({bool ignoreDismissed = false}) async {
    try {
      final response = await http.get(_api, headers: {'User-Agent': 'EnglishWithMovies/$appVersion'}).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final tag = json['tag_name'] as String?;
      final page = Uri.tryParse(json['html_url'] as String? ?? '');
      if (tag == null || page == null || !isNewerVersion(tag, appVersion)) return;
      if (!ignoreDismissed && _dismissedFile.existsSync() && _dismissedFile.readAsStringSync().trim() == tag) return;
      available = (tag, page);
      notifyListeners();
    } catch (_) {
      // Offline: try again next time.
    }
  }

  void download() {
    final page = available?.$2;
    if (page != null) launchUrl(page, mode: LaunchMode.externalApplication);
  }

  /// "Depois": not shown again for this version.
  void dismiss() {
    final tag = available?.$1;
    if (tag != null) _dismissedFile.writeAsStringSync(tag);
    available = null;
    notifyListeners();
  }
}
