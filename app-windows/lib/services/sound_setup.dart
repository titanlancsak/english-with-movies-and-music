import 'package:flutter/foundation.dart';

import 'log.dart';
import 'phonemes.dart';

/// The one-time download that turns on the sound-by-sound analysis.
class SoundSetup extends ChangeNotifier {
  /// 0...1 while downloading.
  double? progress;
  String? error;

  bool get isReady => PhonemeRecognizer.problem == null && PhonemeRecognizer.isModelInstalled;

  /// Why the analysis cannot be installed in this copy of the app, if so.
  String? get problem => PhonemeRecognizer.problem;

  Future<void> install() async {
    if (progress != null) return;
    progress = 0;
    error = null;
    notifyListeners();
    var shown = 0.0;
    try {
      await PhonemeRecognizer.downloadModel((value) {
        // Redraw every 1%, not on every chunk.
        if (value - shown >= 0.01 || value == 1) {
          shown = value;
          progress = value;
          notifyListeners();
        }
      });
    } catch (e) {
      log('Instalação da análise de sons falhou: $e');
      error = e.toString();
    }
    progress = null;
    notifyListeners();
  }
}
