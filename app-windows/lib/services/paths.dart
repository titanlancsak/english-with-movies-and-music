import 'dart:io';

import 'package:path/path.dart' as p;

/// Folders used by the app.
class AppPaths {
  /// %APPDATA%\Santos Lucas\English with Movies & Music on Windows (named after the
  /// company and product in the .exe). Data the user does not browse.
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

  /// [dataFolder] comes from path_provider (see main.dart); this file stays pure Dart so it can be tested.
  static void init(Directory dataFolder) {
    root = _dir(dataFolder.path);
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
