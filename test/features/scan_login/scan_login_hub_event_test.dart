import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/scan_login/application/scan_login_hub.dart';

void main() {
  test('reads granted ticket from current camelCase payload', () {
    const event = ScanLoginHubEvent('granted', <String, dynamic>{
      'scanToken': 'current-ticket',
    });

    expect(event.scanToken, 'current-ticket');
  });

  test('reads granted ticket from legacy PascalCase payload', () {
    const event = ScanLoginHubEvent('granted', <String, dynamic>{
      'ScanToken': 'legacy-ticket',
    });

    expect(event.scanToken, 'legacy-ticket');
  });

  test('reads scanner name from both payload formats', () {
    const current = ScanLoginHubEvent('scanned', <String, dynamic>{
      'scanUserName': 'current-user',
    });
    const legacy = ScanLoginHubEvent('scanned', <String, dynamic>{
      'ScanUserName': 'legacy-user',
    });

    expect(current.scanUserName, 'current-user');
    expect(legacy.scanUserName, 'legacy-user');
  });

  test('does not invent a missing ticket', () {
    const event = ScanLoginHubEvent('granted', <String, dynamic>{});

    expect(event.scanToken, isNull);
  });
}
