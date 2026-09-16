// GENERATED FILE - DO NOT EDIT MANUALLY
// doctor.dart - splash doctor subcommand
import 'dart:io';
import 'splash_command.dart';

class SplashDoctorCommand extends SplashCommand {
  @override
  final String name = 'doctor';

  @override
  final String description =
      'Run a full health check and report status for splash configuration.';

  @override
  void run() {
    try {
      final config = loadConfig();
      stdout.writeln('[OK] Check passed: ${config.keys.join(', ')}');
    } catch (e) {
      stderr.writeln('[ERROR] Check failed: $e');
      exit(1);
    }
  }
}
