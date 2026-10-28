import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/app_update/application/app_update_target.dart';
import 'package:gotoim_flutter/features/app_update/data/models/app_version_dto.dart';

AppVersionDto version({String? package, String? page, bool widget = false}) =>
    AppVersionDto(
      version: '1.0',
      versionCode: 1,
      title: 'update',
      isForce: false,
      pkgUrl: package,
      pageUrl: page,
      isWidget: widget,
    );

void main() {
  test(
    'Android APK downloads and invokes the installer, including file endpoints',
    () {
      for (final url in [
        'https://cdn.example/app.apk?signature=x',
        'https://cdn.example/file?id=1&contentType=application%2Fvnd.android.package-archive',
      ]) {
        final result = planAppUpdate(
          version(package: url, page: 'https://example.com/store'),
          platform: 'android',
        );
        expect(result.action, UpdateAction.installAndroidApk);
        expect(result.url.toString(), url);
      }
    },
  );
  test(
    'Windows downloads recognized installers even when a page is provided',
    () {
      for (final (name, action) in [
        ('setup.exe', UpdateAction.installWindowsExe),
        ('setup.msi', UpdateAction.installWindowsMsi),
      ]) {
        final result = planAppUpdate(
          version(
            package: 'https://cdn.example/$name?signature=x',
            page: 'https://example.com',
          ),
          platform: 'windows',
        );
        expect(result.action, action);
        expect(result.url.path, '/$name');
      }
    },
  );
  test('iOS, desktop, web and widget updates open the page when provided', () {
    for (final platform in ['ios', 'windows', 'macos', 'linux', 'web']) {
      final result = planAppUpdate(
        version(
          package: 'https://cdn.example/app.apk',
          page: 'https://example.com/store',
        ),
        platform: platform,
      );
      expect(result.action, UpdateAction.openUrl);
      expect(result.url.toString(), 'https://example.com/store');
    }
    expect(
      planAppUpdate(
        version(package: 'https://cdn.example/update.wgt', widget: true),
        platform: 'android',
      ).action,
      UpdateAction.openUrl,
    );
  });
  test(
    'non-APK Android links open in the browser and missing or unsafe URLs fail',
    () {
      expect(
        planAppUpdate(
          version(package: 'https://example.com/store'),
          platform: 'android',
        ).action,
        UpdateAction.openUrl,
      );
      for (final value in [
        '/file?id=1',
        'javascript:alert(1)',
        'https://user:pass@example.com/file',
      ]) {
        expect(
          () => planAppUpdate(version(package: value), platform: 'android'),
          throwsFormatException,
        );
      }
      expect(() => planAppUpdate(version(), platform: 'ios'), throwsStateError);
    },
  );
}
