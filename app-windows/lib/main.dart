import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'services/app_controller.dart';
import 'services/log.dart';
import 'services/paths.dart';
import 'ui/home.dart';

/// [args]: a file to open, e.g. from "Open with" in Windows Explorer.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  AppPaths.init(await getApplicationSupportDirectory());
  log('Iniciando (dados em ${AppPaths.root.path})');
  // Unexpected errors go to app.log instead of disappearing silently.
  FlutterError.onError = (details) {
    log('Erro de interface: ${details.exceptionAsString()}');
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    log('Erro: $error\n$stack');
    return true;
  };
  app = AppController();
  runApp(const EnglishWithMoviesApp());
  final file = args.where((arg) => File(arg).existsSync()).firstOrNull;
  if (file != null) unawaited(app.open(file));
}

class EnglishWithMoviesApp extends StatelessWidget {
  const EnglishWithMoviesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'English with Movies & Music',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6366F1), brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF141419),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
