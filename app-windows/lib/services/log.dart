import 'dart:io';

import 'paths.dart';

/// Appends a line to app.log in the app's data folder, to diagnose problems on users' machines.
void log(String message) {
  try {
    final file = AppPaths.file(AppPaths.root, 'app.log');
    // Keep the log small: start over when it passes 1 MB.
    if (file.existsSync() && file.lengthSync() > 1024 * 1024) file.deleteSync();
    file.writeAsStringSync('${DateTime.now().toIso8601String()}  $message\n', mode: FileMode.append, flush: true);
  } catch (_) {}
}
