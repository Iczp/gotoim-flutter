import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/qr_code/data/models/qr_code_models.dart';
import 'package:gotoim_flutter/features/qr_code/data/qr_code_repository.dart';

void main() {
  group('QrCode models & matcher', () {
    test('QrCodeRepository.isPotentialSystemQr matches expected schemes and short links', () {
      expect(QrCodeRepository.isPotentialSystemQr('gotoim://qr/abc123'), isTrue);
      expect(QrCodeRepository.isPotentialSystemQr('gotoim-dev://qr/abc123'), isTrue);
      expect(QrCodeRepository.isPotentialSystemQr('gotoim://user/?id=1001'), isTrue);
      expect(QrCodeRepository.isPotentialSystemQr('https://chat.example.com/q/abc123'), isTrue);
      expect(QrCodeRepository.isPotentialSystemQr('https://chat.example.com/invite/group/xyz'), isTrue);
      expect(QrCodeRepository.isPotentialSystemQr('https://example.com/news'), isFalse);
      expect(QrCodeRepository.isPotentialSystemQr('hello world'), isFalse);
    });

    test('QrCodeDetailModel parses permanent and custom expireDays DTO', () {
      final dto = QrCodeDetailModel.fromJson(<String, dynamic>{
        'id': '00000000-0000-0000-0000-000000000001',
        'code': 'AbCdEf12',
        'scene': 1,
        'ownerId': 1024,
        'isPermanent': false,
        'expireDays': 30,
        'expirationTime': '2026-12-18T00:00:00Z',
        'isEnabled': true,
        'isExpired': false,
        'ownerName': 'AliceShop',
      });

      expect(dto.code, 'AbCdEf12');
      expect(dto.scene, QrCodeScene.chatObjectCard);
      expect(dto.ownerId, 1024);
      expect(dto.isPermanent, isFalse);
      expect(dto.expireDays, 30);
      expect(dto.effectiveContent, 'gotoim://qr/AbCdEf12');
    });

    test('QrCodeScanDataModel parses group invite and card flags', () {
      final scan = QrCodeScanDataModel.fromJson(<String, dynamic>{
        'qrCodeId': '00000000-0000-0000-0000-000000000002',
        'code': 'Grp999',
        'scene': 2,
        'action': 'group_invite',
        'isValid': true,
        'isExpired': false,
        'isDisabled': false,
        'isPermanent': false,
        'expireDays': 7,
        'ownerId': 2048,
        'ownerName': '测试群',
        'memberCount': 12,
        'inviterId': 1001,
        'inviterName': 'Bob',
        'needsApproval': false,
        'isSelf': false,
        'isFriend': false,
        'isAlreadyMember': false,
      });

      expect(scan.isGroup, isTrue);
      expect(scan.isCardOrGroup, isTrue);
      expect(scan.memberCount, 12);
      expect(scan.inviterName, 'Bob');
    });
  });
}
