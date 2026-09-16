// GENERATED FILE - DO NOT EDIT MANUALLY
// apply.dart - splash apply subcommand
import 'dart:io';
import 'splash_command.dart';

class SplashApplyCommand extends SplashCommand {
  @override
  final String name = 'apply';

  @override
  final String description =
      'Generate splash resources for all platforms and write generated Dart config.';

  @override
  void run() {
    final flavor = argResults?['flavor'] as String?;
    final config = loadConfig();
    final merged = mergeFlavor(config, flavor);
    final splash = merged['splash'] as Map? ?? {};
    final startup = merged['startup'] as Map? ?? {};

    // ---------- Mobile (Android / iOS) ----------
    _runFlutterNativeSplash(splash);

    // ---------- Desktop (Windows / macOS) ----------
    _generateDesktopSplash(splash);

    // ---------- Generate Dart constants ----------
    _writeDartConfig(splash, startup);

    stdout.writeln('[OK] Splash apply completed');
  }

  void _runFlutterNativeSplash(Map splash) {
    // Write temporary flutter_native_splash.yaml
    final tempYaml = File('flutter_native_splash.yaml');
    final color = splash['backgroundColor'] ?? '#FFFFFF';
    final image = splash['image'] ?? '';
    final darkImage = splash['darkImage'] ?? '';
    final yamlContent = '''
flutter_native_splash:
  color: "$color"
  image: "$image"
  dark_image: "$darkImage"
  android: true
  ios: true
''';
    tempYaml.writeAsStringSync(yamlContent);
    // Execute the generator
    Process.runSync('flutter', [
      'pub',
      'run',
      'flutter_native_splash:create',
    ], runInShell: true);
    // Clean up
    if (tempYaml.existsSync()) tempYaml.deleteSync();
  }

  void _generateDesktopSplash(Map splash) {
    // Windows
    final winTemplate = File('tool/templates/windows_splash.stub');
    if (winTemplate.existsSync()) {
      final content = winTemplate
          .readAsStringSync()
          .replaceAll(
            '{{BACKGROUND_COLOR}}',
            splash['backgroundColor'] ?? '#FFFFFF',
          )
          .replaceAll('{{IMAGE}}', splash['image'] ?? '')
          .replaceAll(
            '{{TIMEOUT_MS}}',
            (splash['platforms']?['windows']?['timeoutMs'] ?? 5000).toString(),
          );
      final winFile = File('windows/runner/windows_splash.cpp');
      _replaceOrCreateBlock(winFile, content);
    }
    // macOS
    final macTemplate = File('tool/templates/macos_splash.stub');
    if (macTemplate.existsSync()) {
      final content = macTemplate
          .readAsStringSync()
          .replaceAll(
            '{{BACKGROUND_COLOR}}',
            splash['backgroundColor'] ?? '#FFFFFF',
          )
          .replaceAll('{{IMAGE}}', splash['image'] ?? '')
          .replaceAll(
            '{{TIMEOUT_MS}}',
            (splash['platforms']?['macos']?['timeoutMs'] ?? 5000).toString(),
          );
      final macFile = File('macos/Runner/MacOSSplash.swift');
      _replaceOrCreateBlock(macFile, content);
    }
  }

  void _replaceOrCreateBlock(File target, String generatedContent) {
    const beginMarker = '// APP_SPLASH_BEGIN';
    const endMarker = '// APP_SPLASH_END';
    if (!target.existsSync()) {
      // Create file with markers and content
      target.createSync(recursive: true);
      target.writeAsStringSync('$beginMarker\n$generatedContent\n$endMarker\n');
      return;
    }
    final lines = target.readAsLinesSync();
    final startIdx = lines.indexWhere((l) => l.trim() == beginMarker);
    final endIdx = lines.indexWhere((l) => l.trim() == endMarker);
    if (startIdx >= 0 && endIdx > startIdx) {
      final before = lines.sublist(0, startIdx + 1);
      final after = lines.sublist(endIdx);
      final newLines = [...before, generatedContent, ...after];
      target.writeAsStringSync(newLines.join('\n'));
    } else {
      // Append markers at end
      target.writeAsStringSync(
        '\n$beginMarker\n$generatedContent\n$endMarker\n',
        mode: FileMode.append,
      );
    }
  }

  void _writeDartConfig(Map splash, Map startup) {
    final buffer = StringBuffer();
    buffer.writeln('// GENERATED FILE - DO NOT EDIT MANUALLY');
    buffer.writeln(
      "const String splashBackgroundColor = '${splash['backgroundColor'] ?? '#FFFFFF'}';",
    );
    buffer.writeln("const String splashImage = '${splash['image'] ?? ''}';");
    if (splash['darkImage'] != null) {
      buffer.writeln(
        "const String splashDarkImage = '${splash['darkImage']}';",
      );
    }
    if (startup['fadeDurationMs'] != null) {
      buffer.writeln(
        'const int splashFadeDurationMs = ${startup['fadeDurationMs']};',
      );
    }
    final outFile = File('lib/core/startup/generated/splash_config.g.dart');
    outFile.createSync(recursive: true);
    outFile.writeAsStringSync(buffer.toString());
  }
}
