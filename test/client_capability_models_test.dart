import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/capabilities/client_capability_models.dart';

void main() {
  test(
    'network status distinguishes disconnected state and serializes all transports',
    () {
      final disconnected = ClientNetworkStatus(
        types: const <ClientNetworkType>[ClientNetworkType.none],
        observedAt: DateTime.utc(2026, 8, 19),
      );
      final connected = ClientNetworkStatus(
        types: const <ClientNetworkType>[
          ClientNetworkType.wifi,
          ClientNetworkType.vpn,
        ],
        observedAt: DateTime.utc(2026, 8, 19),
      );

      expect(disconnected.isConnected, isFalse);
      expect(connected.isConnected, isTrue);
      expect(connected.toJson()['networkTypes'], <String>['wifi', 'vpn']);
    },
  );
}
