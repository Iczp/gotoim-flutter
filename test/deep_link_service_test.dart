import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/deep_link/deep_link_handler.dart';
import 'package:gotoim_flutter/core/deep_link/deep_link_parser.dart';
import 'package:gotoim_flutter/core/deep_link/deep_link_service.dart';

void main() {
  group('DeepLinkService Event Logging & Execution', () {
    late DeepLinkParser parser;
    late DeepLinkHandler handler;
    late DeepLinkService service;

    setUp(() {
      parser = const DeepLinkParser(
        allowedCustomSchemes: ['gotoim-dev', 'gotoim'],
        allowedHosts: ['gotoim.com'],
      );
      handler = DeepLinkHandler(isAuthenticatedProvider: () => true);
      service = DeepLinkService(parser: parser, handler: handler);
    });

    test('records deep link events in eventLogs', () async {
      expect(service.eventLogs, isEmpty);

      final uri = Uri.parse('gotoim-dev://chat/123/message/456');
      final result = await service.handleUri(uri, source: 'unit_test');

      expect(result.status, DeepLinkExecutionStatus.notImplemented);
      expect(service.eventLogs.length, 1);

      final log = service.eventLogs.first;
      expect(log.source, 'unit_test');
      expect(log.rawUri, uri);
      expect(log.parseResult.isSuccess, isTrue);
      expect(
        log.executionResult?.status,
        DeepLinkExecutionStatus.notImplemented,
      );
    });

    test('clears event logs', () async {
      await service.handleUri(Uri.parse('gotoim-dev://chat/101'));
      await service.handleUri(Uri.parse('gotoim-dev://chat/102'));
      expect(service.eventLogs.length, 2);

      service.clearEventLogs();
      expect(service.eventLogs, isEmpty);
    });

    test('caps event logs at maximum capacity of 50', () async {
      for (int i = 0; i < 60; i++) {
        await service.handleUri(Uri.parse('gotoim-dev://chat/$i'));
      }

      expect(service.eventLogs.length, 50);
      // Newest event should be at index 0 (sessionId = 59)
      expect(service.eventLogs.first.rawUri.toString(), 'gotoim-dev://chat/59');
    });

    test('handles invalid URIs safely without throwing', () async {
      final invalidUri = Uri.parse('gotoim-dev://chat');
      final result = await service.handleUri(invalidUri, source: 'unit_test');

      expect(result.status, DeepLinkExecutionStatus.failed);
      expect(service.eventLogs.length, 1);
      expect(service.eventLogs.first.parseResult.isInvalid, isTrue);
    });
  });
}
