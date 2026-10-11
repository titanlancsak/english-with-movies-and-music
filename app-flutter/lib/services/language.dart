import 'dart:convert';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;

import '../core/dictionary.dart';
import '../core/word_normalizer.dart';

const _userAgent = 'EnglishWithMovies/1.0 (https://github.com/titanlancsak/english-with-movies-and-music)';

/// Definitions from Wiktionary (free, no key), with dictionaryapi.dev as a fallback.
class DictionaryService {
  final _cache = <String, DictionaryEntry?>{};

  Future<DictionaryEntry?> lookup(String word) async {
    for (final candidate in lookupCandidates(word)) {
      if (_cache.containsKey(candidate)) {
        if (_cache[candidate] != null) return _cache[candidate];
        continue;
      }
      final entry = await _wiktionary(candidate) ?? await _dictionaryApi(candidate);
      _cache[candidate] = entry;
      if (entry != null) return entry;
    }
    return null;
  }

  Future<DictionaryEntry?> _wiktionary(String word) async {
    try {
      final response = await http
          .get(Uri.parse('https://en.wiktionary.org/api/rest_v1/page/definition/${Uri.encodeComponent(word)}'),
              headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      return parseWiktionary(word, jsonDecode(response.body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<DictionaryEntry?> _dictionaryApi(String word) async {
    try {
      final response = await http
          .get(Uri.parse('https://api.dictionaryapi.dev/api/v2/entries/en/${Uri.encodeComponent(word)}'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      return parseDictionaryApi(jsonDecode(response.body) as List<dynamic>);
    } catch (_) {
      return null;
    }
  }
}

/// English -> Portuguese with the free MyMemory API (about 5,000 characters per day without a key).
class Translator {
  final _cache = <String, String>{};
  String? problem;

  String? cached(String text) => _cache[text.trim()];

  Future<String?> translate(String text) async {
    final source = text.trim();
    if (source.isEmpty) return null;
    if (_cache.containsKey(source)) return _cache[source];
    try {
      final uri = Uri.https('api.mymemory.translated.net', '/get', {'q': source, 'langpair': 'en|pt-BR'});
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final translated = (json['responseData'] as Map?)?['translatedText'] as String?;
      if (response.statusCode != 200 || translated == null || json['quotaFinished'] == true) {
        problem = 'O limite diário gratuito de traduções acabou. Volta amanhã.';
        return null;
      }
      problem = null;
      return _cache[source] = translated;
    } catch (_) {
      problem = 'Sem conexão para traduzir.';
      return null;
    }
  }
}

/// Pronunciation with the system voices (Windows SAPI / macOS).
class Speaker {
  Speaker() {
    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.45);
  }

  final _tts = FlutterTts();

  Future<void> say(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }
}
