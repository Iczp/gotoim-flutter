// GENERATED FILE – DO NOT EDIT MANUALLY
// doctor.dart – splash doctor subcommand
import ''dart:io'';
import ''package:args/command_runner.dart'';
import ''splash_command.dart'';

class SplashDoctorCommand extends SplashCommand {
  @override
  final String name = ''doctor'';

  @override
  final String description = ''Run a full health check and report status for splash configuration.'';

  @override
  void run() {
    // Run check first
    try {
      final checkCmd = SplashCheckCommand();
      checkCmd.run();
      stdout.writeln(''[OK] Check passed'');
    } catch (e) {
      stderr.writeln(''[ERROR] Check failed: '');
      exit(1);
    }

    // Dry run apply to see what would be generated
    try {
      final dryRunCmd = SplashDryRunCommand();
      dryRunCmd.run();
      stdout.writeln(''[OK] Dry‑run apply succeeded'');
    } catch (e) {
      stderr.writeln(''[ERROR] Dry‑run apply failed: '');
      exit(1);
    }
  }
}
