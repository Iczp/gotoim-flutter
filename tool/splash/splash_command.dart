// GENERATED FILE – DO NOT EDIT MANUALLY
// splash_command.dart – base class for splash subcommands
import 'package:args/command_runner.dart';
import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:path/path.dart' as p;

/// Common utilities for all splash commands.
abstract class SplashCommand extends Command {
  /// Path to the configuration file.
  final String configPath = p.normalize(p.join('config', 'splash.yaml'));

  /// Load the YAML configuration as a map.
  Map<String, dynamic> loadConfig() {
    final file = File(configPath);
    if (!file.existsSync()) {
      throw Exception('Splash configuration not found at $configPath');
    }
    final content = file.readAsStringSync();
    return loadYaml(content) as Map<String, dynamic>;
  }

  /// Merge flavor overrides if a flavor is supplied via --flavor.
  Map<String, dynamic> mergeFlavor(Map<String, dynamic> base, String? flavor) {
    if (flavor == null) return base;
    final flavors = base['flavors'] as Map? ?? {};
    final override = flavors[flavor] as Map?;
    if (override == null) return base;
    // Deep merge – simple recursive implementation.
    final result = Map<String, dynamic>.from(base);
    void deepMerge(Map target, Map source) {
      source.forEach((key, value) {
        if (value is Map && target[key] is Map) {
          deepMerge(
            target[key] as Map,
            value,
          );
        } else {
          target[key] = value;
        }
      });
    }

    deepMerge(result, override);
    return result;
  }
}
