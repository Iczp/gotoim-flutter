import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/workbench/data/workbench_models.dart';
import 'package:gotoim_flutter/features/workbench/data/workbench_repository.dart';

void main() {
  group('WorkbenchModels', () {
    test('WorkbenchApp serializes to and from JSON', () {
      final app = WorkbenchApp(
        appId: 'crm',
        name: 'CRM',
        url: Uri.parse('https://crm.gotoim.com/dashboard'),
        iconUrl: 'https://cdn.gotoim.com/icons/crm.png',
        type: WorkbenchAppType.web,
        openMode: AppOpenMode.systemTask,
        reuseExisting: true,
        authMode: MiniAppAuthMode.silent,
        sort: 10,
        enabled: true,
      );

      final json = app.toJson();
      expect(json['appId'], 'crm');
      expect(json['name'], 'CRM');
      expect(json['url'], 'https://crm.gotoim.com/dashboard');
      expect(json['type'], 'web');
      expect(json['openMode'], 'systemTask');
      expect(json['reuseExisting'], true);
      expect(json['authMode'], 'silent');

      final fromJson = WorkbenchApp.fromJson(json);
      expect(fromJson.appId, app.appId);
      expect(fromJson.name, app.name);
      expect(fromJson.url, app.url);
      expect(fromJson.type, app.type);
      expect(fromJson.openMode, app.openMode);
      expect(fromJson.reuseExisting, app.reuseExisting);
      expect(fromJson.authMode, app.authMode);
      expect(fromJson.sort, app.sort);
      expect(fromJson.enabled, app.enabled);
    });

    test('MiniAppLaunchRequest serializes correctly', () {
      final request = MiniAppLaunchRequest.fromJson(<String, dynamic>{
        'appId': 'oa',
        'url': 'https://oa.gotoim.com/approval/456',
        'title': 'OA 审批',
      });

      expect(request.appId, 'oa');
      expect(request.url, Uri.parse('https://oa.gotoim.com/approval/456'));
      expect(request.title, 'OA 审批');
    });
  });

  group('MockWorkbenchRepository', () {
    test('returns default enabled apps sorted by sort field', () async {
      final repo = MockWorkbenchRepository();
      final apps = await repo.getApps();

      expect(apps.length, 2);
      expect(apps[0].appId, 'crm');
      expect(apps[1].appId, 'oa');
    });

    test('supports dynamic add, remove, and reset', () async {
      final repo = MockWorkbenchRepository();

      repo.addApp(
        WorkbenchApp(
          appId: 'erp',
          name: 'ERP',
          url: Uri.parse('https://erp.gotoim.com'),
          sort: 5,
        ),
      );

      var apps = await repo.getApps();
      expect(apps.length, 3);
      expect(apps[0].appId, 'erp'); // sort: 5 comes first

      final removed = repo.removeApp('erp');
      expect(removed, isTrue);

      apps = await repo.getApps();
      expect(apps.length, 2);

      repo.reset();
      apps = await repo.getApps();
      expect(apps.length, 2);
    });
  });
}
