import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/services/file/attachment_cache.dart';
import 'package:gotoim_flutter/core/services/file/storage_path_service.dart';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _MockPathProvider extends PathProviderPlatform {
  _MockPathProvider(this.tempPath);
  final String tempPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => tempPath;

  @override
  Future<String?> getApplicationSupportPath() async => tempPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final secureStorageData = <String, String>{};
  late StoragePathService service;
  late Directory tempTestDir;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        final args = call.arguments is Map ? call.arguments as Map : null;
        final key = args?['key'] as String?;
        switch (call.method) {
          case 'read':
            return key != null ? secureStorageData[key] : null;
          case 'write':
            if (key != null) {
              final val = args?['value'] as String?;
              if (val != null) {
                secureStorageData[key] = val;
              } else {
                secureStorageData.remove(key);
              }
            }
            return null;
          case 'delete':
            if (key != null) {
              secureStorageData.remove(key);
            }
            return null;
          case 'deleteAll':
            secureStorageData.clear();
            return null;
          default:
            return null;
        }
      },
    );
  });

  setUp(() async {
    secureStorageData.clear();
    tempTestDir = await Directory.systemTemp.createTemp('gotoim_storage_test_');
    PathProviderPlatform.instance = _MockPathProvider(tempTestDir.path);
    service = StoragePathService(storage: const FlutterSecureStorage());
  });

  tearDown(() async {
    if (await tempTestDir.exists()) {
      await tempTestDir.delete(recursive: true);
    }
  });

  group('StoragePathService Tests', () {
    test('1. 默认存储路径获取与格式化', () async {
      final defaultPath = await service.getDefaultPath();
      expect(defaultPath, isNotEmpty);
      expect(defaultPath, contains('LocalShare'));
      expect(defaultPath, contains('聊天文件'));

      final activePath = await service.getActiveStoragePath();
      expect(activePath, equals(defaultPath));
    });

    test('2. 自定义路径持久化、读取与重置', () async {
      final customDir = Directory('${tempTestDir.path}/CustomFiles');
      await service.setCustomPath(customDir.path);

      final saved = await service.getCustomPath();
      expect(saved, equals(customDir.path));

      final active = await service.getActiveStoragePath();
      expect(active, equals(customDir.path));

      // 验证目录被自动创建
      expect(await customDir.exists(), isTrue);

      // 重置回默认
      await service.resetToDefault();
      expect(await service.getCustomPath(), isNull);
      expect(await service.getActiveStoragePath(), equals(await service.getDefaultPath()));
    });

    test('3. 目录统计 calculateDirectoryStats 与容量格式化', () async {
      final subDir = Directory('${tempTestDir.path}/StatsDir');
      await subDir.create(recursive: true);

      final file1 = File('${subDir.path}/test1.txt');
      await file1.writeAsString('Hello GotoIM');

      final file2 = File('${subDir.path}/test2.bin');
      await file2.writeAsBytes(Uint8List(2048));

      final stats = await service.calculateDirectoryStats(subDir.path);
      expect(stats.fileCount, equals(2));
      expect(stats.totalBytes, equals(12 + 2048));
      expect(stats.formattedBytes, contains('KB'));
    });

    test('4. 文件无损迁移 migrateFiles (保持子目录结构与进度回调)', () async {
      final sourceDir = Directory('${tempTestDir.path}/Source');
      final targetDir = Directory('${tempTestDir.path}/Target');

      // 创建多层级文件结构: user/target/category/date/file
      final file1 = File('${sourceDir.path}/u1/t1/doc/2026-10-18/report.pdf');
      await file1.parent.create(recursive: true);
      await file1.writeAsString('Sample Report Content');

      final file2 = File('${sourceDir.path}/u1/t2/img/2026-10-18/photo.png');
      await file2.parent.create(recursive: true);
      await file2.writeAsBytes(Uint8List(512));

      int lastProgress = 0;
      int totalProgress = 0;

      final result = await service.migrateFiles(
        sourcePath: sourceDir.path,
        targetPath: targetDir.path,
        deleteSourceFiles: true,
        onProgress: (cur, tot) {
          lastProgress = cur;
          totalProgress = tot;
        },
      );

      expect(result.success, isTrue);
      expect(result.migratedCount, equals(2));
      expect(lastProgress, equals(2));
      expect(totalProgress, equals(2));

      // 验证目标目录结构完整性
      final destFile1 = File('${targetDir.path}/u1/t1/doc/2026-10-18/report.pdf');
      expect(await destFile1.exists(), isTrue);
      expect(await destFile1.readAsString(), equals('Sample Report Content'));

      final destFile2 = File('${targetDir.path}/u1/t2/img/2026-10-18/photo.png');
      expect(await destFile2.exists(), isTrue);
      expect((await destFile2.readAsBytes()).length, equals(512));

      // 验证源文件已删除
      expect(await file1.exists(), isFalse);
      expect(await file2.exists(), isFalse);

      // 验证自定义路径已更新为 targetDir
      expect(await service.getActiveStoragePath(), equals(targetDir.path));
    });

    test('5. AttachmentCache 动态注入自定义路径与历史查找回退', () async {
      final customDir = Directory('${tempTestDir.path}/CacheRoot');
      await customDir.create(recursive: true);

      final cache = createAttachmentCache(
        storagePathResolver: () async => customDir.path,
      );

      // 写入附件
      final writtenPath = await cache.write(
        'att_key_001',
        'contract.docx',
        Uint8List.fromList('Contract Body'.codeUnits),
        userId: 'admin',
        chatTarget: 'client_01',
        category: '文档',
        messageDate: DateTime(2026, 10, 18),
      );

      expect(writtenPath, isNotNull);
      expect(writtenPath, startsWith(customDir.path));
      expect(File(writtenPath!).existsSync(), isTrue);

      // 在自定义路径下查找
      final found = await cache.find(
        'att_key_001',
        'contract.docx',
        userId: 'admin',
        chatTarget: 'client_01',
      );
      expect(found, equals(writtenPath));
    });
  });
}
