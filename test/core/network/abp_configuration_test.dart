import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/network/abp/abp_application_configuration_dto.dart';
import 'package:gotoim_flutter/core/network/abp/abp_configuration_api.dart';
import 'package:gotoim_flutter/core/network/abp/abp_configuration_repository.dart';
import 'package:gotoim_flutter/core/network/abp/abp_current_user.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/core/database/unified_database.dart';
import 'package:gotoim_flutter/features/auth/application/auth_controller.dart';
import 'package:gotoim_flutter/features/auth/domain/auth_repository.dart';
import 'package:gotoim_flutter/features/auth/domain/auth_session.dart';
import 'package:gotoim_flutter/core/realtime/signalr_gateway.dart';

const Map<String, dynamic> _kSampleCurrentUserJson = {
  'isAuthenticated': true,
  'id': '360cfedb-e92d-3331-1fad-3a086371e0e4',
  'tenantId': null,
  'impersonatorUserId': null,
  'impersonatorTenantId': null,
  'impersonatorUserName': null,
  'impersonatorTenantName': null,
  'userName': 'admin',
  'name': 'IM',
  'surName': 'Goto',
  'email': 'admin@gotoim.com',
  'emailVerified': false,
  'phoneNumber': '186****9806',
  'phoneNumberVerified': false,
  'roles': ['admin'],
  'sessionId': null,
};

const Map<String, dynamic> _kSampleAppConfigJson = {
  'currentUser': _kSampleCurrentUserJson,
  'auth': {
    'policies': {'AbpIdentity.Users': true},
    'grantedPolicies': {'AbpIdentity.Users': true},
  },
  'setting': {
    'values': {'Abp.Localization.DefaultLanguage': 'zh-Hans'},
  },
  'features': {
    'values': {'Chat.MaxMessageLength': '4000'},
  },
};

class FakeApiClient implements ApiClient {
  FakeApiClient({this.response = _kSampleAppConfigJson});

  Map<String, dynamic> response;
  int callCount = 0;
  String? lastPath;
  Map<String, Object?>? lastQuery;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) async {
    callCount++;
    lastPath = path;
    lastQuery = query;
    return response as T;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeUnifiedDatabase implements UnifiedDatabase {
  final Map<String, String> settings = {};

  @override
  Future<String?> readSettingValue(String id) async => settings[id];

  @override
  Future<void> writeSettingValue({
    required String id,
    required String group,
    required String value,
  }) async {
    settings[id] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuthRepository implements AuthRepository {
  bool restoreSuccess = true;
  @override
  Future<bool> restoreSession() async => restoreSuccess;
  @override
  Future<void> login({
    required String username,
    required String password,
  }) async {}
  @override
  Future<void> register({
    required String username,
    required String password,
    String? emailAddress,
  }) async {}
  @override
  Future<void> loginWithScanToken(String scanToken) async {}
  @override
  Future<String> getClientCredentialsAccessToken() async => 'fake-token';
  @override
  Future<void> logout() async {}
  @override
  Future<AuthSession> refreshSession() async => const AuthSession(
    accessToken: 'new-token',
    refreshToken: 'new-refresh',
    expiresIn: Duration(hours: 1),
  );
  @override
  Future<Map<String, dynamic>> getUserInfo() async => {'name': 'Fallback Name'};
  @override
  Future<Map<String, dynamic>> introspect(
    RevocationTokenType tokenType,
  ) async => {};
  @override
  Future<void> revoke(RevocationTokenType tokenType) async {}
}

class FakeSignalRGateway implements SignalRGateway {
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('AbpCurrentUser DTO', () {
    test('deserializes user-provided JSON accurately', () {
      final user = AbpCurrentUser.fromJson(_kSampleCurrentUserJson);

      expect(user.isAuthenticated, isTrue);
      expect(user.id, '360cfedb-e92d-3331-1fad-3a086371e0e4');
      expect(user.userName, 'admin');
      expect(user.name, 'IM');
      expect(user.surName, 'Goto');
      expect(user.email, 'admin@gotoim.com');
      expect(user.emailVerified, isFalse);
      expect(user.phoneNumber, '186****9806');
      expect(user.phoneNumberVerified, isFalse);
      expect(user.roles, ['admin']);
      expect(user.sessionId, isNull);
      expect(user.tenantId, isNull);

      // Display name and full name
      expect(user.displayName, 'IM');
      expect(user.fullName, 'Goto IM');
    });

    test('displayName fallbacks appropriately', () {
      const userWithoutName = AbpCurrentUser(
        isAuthenticated: true,
        userName: 'fallback_user',
      );
      expect(userWithoutName.displayName, 'fallback_user');

      const userWithPhoneOnly = AbpCurrentUser(
        isAuthenticated: true,
        phoneNumber: '13800000000',
      );
      expect(userWithPhoneOnly.displayName, '13800000000');

      const anonymousUser = AbpCurrentUser();
      expect(anonymousUser.displayName, '未命名用户');
    });

    test('toJson and fromJson round-trip preserves fields', () {
      final user = AbpCurrentUser.fromJson(_kSampleCurrentUserJson);
      final json = user.toJson();
      final roundTrip = AbpCurrentUser.fromJson(json);

      expect(roundTrip, equals(user));
      expect(roundTrip.id, user.id);
      expect(roundTrip.roles, user.roles);
    });
  });

  group('AbpApplicationConfigurationDto', () {
    test('parses currentUser, auth, setting, features from raw JSON', () {
      final config = AbpApplicationConfigurationDto.fromJson(
        _kSampleAppConfigJson,
      );

      expect(config.currentUser.id, '360cfedb-e92d-3331-1fad-3a086371e0e4');
      expect(config.currentUser.userName, 'admin');
      expect(config.auth?['policies']?['AbpIdentity.Users'], isTrue);
      expect(
        config.setting?['values']?['Abp.Localization.DefaultLanguage'],
        'zh-Hans',
      );
      expect(config.features?['values']?['Chat.MaxMessageLength'], '4000');
    });
  });

  group('AbpConfigurationRepository with SQLite Cache', () {
    test('fetches from API and caches to SQLite', () async {
      final fakeApi = FakeApiClient();
      final api = AbpConfigurationApi(fakeApi);
      final fakeDb = FakeUnifiedDatabase();
      final repo = AbpConfigurationRepository(api: api, database: fakeDb);

      expect(await repo.loadCachedConfiguration(), isNull);

      final config = await repo.fetchAndCacheConfiguration();

      expect(fakeApi.callCount, 1);
      expect(fakeApi.lastPath, '/api/abp/application-configuration');
      expect(fakeApi.lastQuery?['IncludeLocalizationResources'], isFalse);
      expect(config.currentUser.userName, 'admin');

      // Check that it wrote to fakeDb
      expect(fakeDb.settings['abp_application_configuration'], isNotNull);
      expect(
        fakeDb.settings['abp_application_configuration_cached_at'],
        isNotNull,
      );

      // Subsequent loadCachedConfiguration returns cached data without calling API
      final cached = await repo.loadCachedConfiguration();
      expect(cached, isNotNull);
      expect(cached!.currentUser.id, '360cfedb-e92d-3331-1fad-3a086371e0e4');
      expect(fakeApi.callCount, 1); // Not called again!

      // Clear cache
      await repo.clearCache();
      expect(await repo.loadCachedConfiguration(), isNull);
    });
  });

  group(
    'AuthController ABP Application Configuration & Current User Integration',
    () {
      test(
        'restoring session fetches application configuration and sets currentUser as current account',
        () async {
          final fakeApi = FakeApiClient();
          final api = AbpConfigurationApi(fakeApi);
          final fakeDb = FakeUnifiedDatabase();
          final repo = AbpConfigurationRepository(api: api, database: fakeDb);
          final authRepo = FakeAuthRepository()..restoreSuccess = true;
          final signalR = FakeSignalRGateway();

          final controller = AuthController(
            authRepo,
            signalR,
            abpConfigurationRepository: repo,
          );

          // Wait for async restore & fetch
          await Future<void>.delayed(const Duration(milliseconds: 50));

          expect(controller.status, AuthStatus.authenticated);
          expect(controller.currentUser, isNotNull);
          expect(
            controller.currentUser!.id,
            '360cfedb-e92d-3331-1fad-3a086371e0e4',
          );
          expect(controller.currentUser!.userName, 'admin');
          expect(controller.accountName, 'IM'); // displayName from currentUser
          expect(controller.applicationConfiguration, isNotNull);
        },
      );

      test('loads offline cache first before network call completes', () async {
        final fakeDb = FakeUnifiedDatabase();
        // Pre-seed offline cache in database
        fakeDb.settings['abp_application_configuration'] = jsonEncode(
          _kSampleAppConfigJson,
        );

        final fakeApi = FakeApiClient();
        final api = AbpConfigurationApi(fakeApi);
        final repo = AbpConfigurationRepository(api: api, database: fakeDb);
        final authRepo = FakeAuthRepository()..restoreSuccess = true;
        final signalR = FakeSignalRGateway();

        final controller = AuthController(
          authRepo,
          signalR,
          abpConfigurationRepository: repo,
        );

        // Give microtask time to read cached config
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(controller.currentUser, isNotNull);
        expect(controller.currentUser!.userName, 'admin');
        expect(controller.accountName, 'IM');
      });
    },
  );
}
