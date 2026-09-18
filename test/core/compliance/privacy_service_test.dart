import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/compliance/privacy_service.dart';

class FakeFlutterSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _data[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }
}

void main() {
  group('PrivacyService', () {
    late FakeFlutterSecureStorage storage;
    late PrivacyService service;

    setUp(() {
      storage = FakeFlutterSecureStorage();
      service = PrivacyService(storage: storage);
    });

    test('initial state before initialize()', () {
      expect(service.isInitialized, isFalse);
      expect(service.hasAgreed, isFalse);
      expect(service.agreedAt, isNull);
    });

    test('initialize returns false when no record exists', () async {
      final result = await service.initialize();
      expect(result, isFalse);
      expect(service.hasAgreed, isFalse);
      expect(service.isInitialized, isTrue);
    });

    test('saveAgreement persists state and updates notifyListeners', () async {
      await service.initialize();
      var notified = false;
      service.addListener(() => notified = true);

      await service.saveAgreement();

      expect(notified, isTrue);
      expect(service.hasAgreed, isTrue);
      expect(service.agreedAt, isNotNull);

      // Re-initialize from storage in new instance
      final newService = PrivacyService(storage: storage);
      final restored = await newService.initialize();
      expect(restored, isTrue);
      expect(newService.hasAgreed, isTrue);
      expect(newService.agreedAt, isNotNull);
    });

    test('resetAgreement clears state and persists revocation', () async {
      await service.saveAgreement();
      expect(service.hasAgreed, isTrue);

      await service.resetAgreement();
      expect(service.hasAgreed, isFalse);
      expect(service.agreedAt, isNull);

      final newService = PrivacyService(storage: storage);
      final restored = await newService.initialize();
      expect(restored, isFalse);
      expect(newService.hasAgreed, isFalse);
    });

    test('provides comprehensive agreement titles and legal content', () {
      expect(PrivacyService.userAgreementTitle, contains('用户服务协议'));
      expect(PrivacyService.privacyPolicyTitle, contains('隐私保护政策'));
      expect(PrivacyService.userAgreementContent, contains('用户行为准则'));
      expect(PrivacyService.privacyPolicyContent, contains('个人信息'));
    });
  });
}
