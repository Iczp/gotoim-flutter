import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/app_update/data/models/app_version_dto.dart';

void main() {
  group('AppVersionDto', () {
    test('parses from standard camelCase JSON correctly', () {
      final json = {
        'id': 'v-1.2.0',
        'platform': 'android',
        'version': '1.2.0',
        'versionCode': 120,
        'title': 'New Version Available',
        'content': 'Feature improvements and bug fixes.',
        'pkgUrl': 'https://download.example.com/app-release.apk',
        'pageUrl': 'https://gotoim.com/download',
        'isForce': true,
        'isWidget': false,
        'isPublic': true,
        'isEnabled': true,
      };

      final dto = AppVersionDto.fromJson(json);

      expect(dto.id, 'v-1.2.0');
      expect(dto.platform, 'android');
      expect(dto.version, '1.2.0');
      expect(dto.versionCode, 120);
      expect(dto.title, 'New Version Available');
      expect(dto.content, 'Feature improvements and bug fixes.');
      expect(dto.pkgUrl, 'https://download.example.com/app-release.apk');
      expect(dto.pageUrl, 'https://gotoim.com/download');
      expect(dto.isForce, isTrue);
      expect(dto.isWidget, isFalse);
      expect(dto.isPublic, isTrue);
      expect(dto.isEnabled, isTrue);
    });

    test('parses from ABP vNext PascalCase JSON correctly', () {
      final json = {
        'Id': 'v-2.0.0',
        'Platform': 'Android',
        'Version': '2.0.0',
        'VersionCode': 200,
        'Title': 'Major Update',
        'Content': 'Brand new UI revamp.',
        'PkgUrl': 'https://download.example.com/app-v2.apk',
        'PageUrl': 'https://gotoim.com/releases/v2',
        'IsForce': false,
        'IsWidget': true,
        'IsPublic': true,
        'IsEnabled': true,
      };

      final dto = AppVersionDto.fromJson(json);

      expect(dto.id, 'v-2.0.0');
      expect(dto.platform, 'Android');
      expect(dto.version, '2.0.0');
      expect(dto.versionCode, 200);
      expect(dto.title, 'Major Update');
      expect(dto.content, 'Brand new UI revamp.');
      expect(dto.pkgUrl, 'https://download.example.com/app-v2.apk');
      expect(dto.pageUrl, 'https://gotoim.com/releases/v2');
      expect(dto.isForce, isFalse);
      expect(dto.isWidget, isTrue);
    });

    test('toJson serializes correctly', () {
      const dto = AppVersionDto(
        id: 'test-1',
        version: '1.0.0',
        versionCode: 100,
        title: 'Initial Release',
        isForce: false,
        pkgUrl: 'https://example.com/file.apk',
      );

      final json = dto.toJson();
      expect(json['id'], 'test-1');
      expect(json['version'], '1.0.0');
      expect(json['versionCode'], 100);
      expect(json['title'], 'Initial Release');
      expect(json['isForce'], isFalse);
      expect(json['pkgUrl'], 'https://example.com/file.apk');
    });
  });
}
