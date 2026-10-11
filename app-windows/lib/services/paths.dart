import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Folders used by the app.
class AppPaths {
  /// %APPDATA%\com.titanlancsak\english_with_movies (data the user does not browse).
  static late Directory root;
  static late Directory models;
  static late Directory transcripts;
  static late Directory thumbnails;
  static late Directory practice;
  static late Directory work;

  /// Videos\English with Movies: downloaded videos, kept where the user can find them.
  static late Directory downloads;

  /// ffmpeg, yt-dlp and whisper.cpp shipped next to the app (see the release workflow).
  static late Directory tools;

  static Future<void> init() async {
    root = await getApplicationSupportDirectory();
    models = _dir(p.join(root.path, 'models'));
    transcripts = _dir(p.join(root.path, 'transcripts'));
    thumbnails = _dir(p.join(root.path, 'thumbnails'));
    practice = _dir(p.join(root.path, 'practice'));
    work = _dir(p.join(root.path, 'work'));

    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    final videos = home != null ? p.join(home, Platform.isMacOS ? 'Movies' : 'Videos') : root.path;
    downloads = _dir(p.join(videos, 'English with Movies'));
    tools = Directory(p.join(p.dirname(Platform.resolvedExecutable), 'tools'));
  }

  static Directory _dir(String path) => Directory(path)..createSync(recursive: true);

  static File file(Directory dir, String name) => File(p.join(dir.path, name));
}
