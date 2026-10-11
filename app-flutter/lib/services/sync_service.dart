import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/sync.dart';
import 'log.dart';
import 'paths.dart';
import 'stores.dart';

/// Keeps saved words, pronunciation history and study time in a file shared between devices.
///
/// On a computer the file lives in a folder the user chooses (Google Drive, Dropbox, OneDrive,
/// iCloud Drive) and is synced automatically. A phone cannot write into those folders, so there
/// the user imports the file (merging it) and saves it back.
class SyncService extends ChangeNotifier {
  SyncService(this.words, this.practice, this.study) {
    final settings = _settings;
    folder = settings['folder'] as String?;
    if (folder != null) {
      words.addListener(_scheduleSync);
      practice.addListener(_scheduleSync);
      _timer = Timer.periodic(const Duration(minutes: 2), (_) => syncNow());
      syncNow();
    }
  }

  final SavedWordsStore words;
  final PracticeStore practice;
  final StudyStore study;

  /// The synced folder (computers only).
  String? folder;
  String status = '';
  Timer? _timer, _debounce;
  bool _syncing = false;

  File get _settingsFile => AppPaths.file(AppPaths.root, 'sync.json');

  Map<String, dynamic> get _settings {
    try {
      return jsonDecode(_settingsFile.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  File? get file => folder == null ? null : File(p.join(folder!, SyncDocument.fileName));

  void setFolder(String? value) {
    folder = value;
    _settingsFile.writeAsStringSync(jsonEncode({'folder': value}));
    words.removeListener(_scheduleSync);
    practice.removeListener(_scheduleSync);
    _timer?.cancel();
    status = '';
    if (value != null) {
      words.addListener(_scheduleSync);
      practice.addListener(_scheduleSync);
      _timer = Timer.periodic(const Duration(minutes: 2), (_) => syncNow());
      syncNow();
    }
    notifyListeners();
  }

  void _scheduleSync() {
    if (_syncing) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), syncNow);
  }

  /// Merges the folder's file into the local data and writes the result back.
  Future<void> syncNow() async {
    final target = file;
    if (target == null || _syncing) return;
    _syncing = true;
    try {
      final existing = target.existsSync() ? await target.readAsString() : null;
      if (existing != null) _merge(existing);
      final merged = _encode();
      if (merged != existing) await target.writeAsString(merged, flush: true);
      final now = DateTime.now();
      status = 'Sincronizado às ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    } catch (error) {
      log('Sincronização falhou: $error');
      status = 'Não foi possível sincronizar: $error';
    }
    _syncing = false;
    notifyListeners();
  }

  void _merge(String json) {
    study.save();
    final remote = SyncDocument.fromJson(jsonDecode(json) as Map<String, dynamic>);
    SyncDocument.merge(remote, words: words.list, practice: practice.history, study: study.log);
    words.saveAfterSync();
    practice.saveAfterSync();
    study.save();
  }

  String _encode() => const JsonEncoder.withIndent('  ').convert(SyncDocument.of(words.list, practice.history, study.log).toJson());

  // MARK: Phones: import and save the file by hand

  /// Picks the sync file (e.g. from Google Drive) and merges it into this phone's data.
  Future<bool> importFile() async {
    final picked = await FilePicker.pickFile(type: FileType.any);
    final path = picked?.path;
    if (path == null) return false;
    try {
      _syncing = true;
      _merge(await File(path).readAsString());
      status = 'Dados do arquivo juntados com os deste aparelho.';
      return true;
    } catch (error) {
      status = 'Este arquivo não é de sincronização do app: $error';
      return false;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// Saves this device's data (already merged) as a sync file, e.g. into Google Drive.
  Future<void> exportFile() async {
    final saved = await FilePicker.saveFile(
      dialogTitle: 'Salvar arquivo de sincronização',
      fileName: SyncDocument.fileName,
      bytes: Uint8List.fromList(utf8.encode(_encode())),
      mimeType: 'application/json',
    );
    if (saved != null) {
      status = 'Arquivo salvo. Abra-o nos outros aparelhos para juntar os dados.';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}
