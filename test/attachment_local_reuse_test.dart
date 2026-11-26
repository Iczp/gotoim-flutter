import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/database/unified_database.dart';
import 'package:gotoim_flutter/core/device/client_device_context.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/core/services/file/attachment_cache.dart';
import 'package:gotoim_flutter/core/services/file/attachment_transfer_service.dart';
import 'package:gotoim_flutter/core/services/file/file_picker_service.dart';
import 'package:gotoim_flutter/core/widgets/two_line_app_bar_title.dart';
import 'package:gotoim_flutter/features/auth/data/openid_connect_auth_repository.dart';
import 'package:gotoim_flutter/features/chat/data/datasources/message_api.dart';
import 'package:gotoim_flutter/features/chat/data/datasources/message_dao.dart';
import 'package:gotoim_flutter/features/chat/data/repositories/message_repository.dart';
import 'package:image_picker/image_picker.dart';

class _TrackingApiClient extends Fake implements ApiClient {
  int getBytesCalls = 0;

  @override
  Future<List<int>> getBytes(
    String path, {
    Map<String, Object?>? query,
    Object? cancelTag,
    void Function(int received, int total)? onProgress,
  }) async {
    getBytesCalls++;
    return <int>[1, 2, 3];
  }
}

class _FakeAttachmentCache implements AttachmentCache {
  final Set<String> openedPaths = <String>{};

  @override
  Future<bool> exists(String path) async {
    final f = File(path);
    return await f.exists() && await f.length() > 0;
  }

  @override
  Future<String?> find(
    String key,
    String fileName, {
    String? userId,
    String? chatTarget,
    DateTime? messageDate,
    String? category,
  }) async =>
      null;

  @override
  Future<void> open(String path) async {
    openedPaths.add(path);
  }

  @override
  Future<Uint8List?> readBytes(String path) async {
    if (!await exists(path)) return null;
    return File(path).readAsBytes();
  }

  @override
  Future<String?> write(
    String key,
    String fileName,
    Uint8List bytes, {
    String? userId,
    String? chatTarget,
    DateTime? messageDate,
    String? category,
  }) async =>
      null;
}

class _FakeFilePickerService extends Fake implements FilePickerService {
  FileSaveRequest? lastSaveRequest;

  @override
  Future<SavedFile?> saveFile(FileSaveRequest request) async {
    lastSaveRequest = request;
    return SavedFile(uri: Uri.file(request.fileName));
  }
}

class _FakeUploadMessageApi extends Fake implements MessageApi {
  @override
  Future<Map<String, dynamic>> sendUploadFile({
    required String sessionUnitId,
    required String fileName,
    required int fileLength,
    required Stream<List<int>> Function() openRead,
    int messageType = 5,
    Map<String, Object?>? extraFields,
    Map<String, MultipartUploadFile>? extraFiles,
    void Function(int sent, int total)? onProgress,
  }) async {
    return <String, dynamic>{
      'id': 98765,
      'messageType': messageType,
      'creationTime': '2026-11-26T08:00:00Z',
      'content': <String, dynamic>{
        'fileName': fileName,
        'size': fileLength,
        'url': '/api/chat/file/download/abc',
      },
    };
  }
}

void main() {
  test(
    'AttachmentTransferService reuses uploaded localFilePath without re-downloading',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('gotoim_attach_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final localFile = File('${tempDir.path}/report.pdf');
      await localFile.writeAsBytes(Uint8List.fromList([10, 20, 30, 40]));

      dotenv.loadFromString(envString: 'API_BASE_URL=https://example.test');
      final env = AppEnvironment.fromDotEnv(AppFlavor.development);
      final client = _TrackingApiClient();
      final cache = _FakeAttachmentCache();
      final picker = _FakeFilePickerService();
      final service = AttachmentTransferService(
        client: client,
        environment: env,
        filePickerService: picker,
        cache: cache,
      );

      // Opening with localFilePath directly opens the local file with zero HTTP download calls.
      await service.open(
        id: 'msg-1',
        source: '/api/chat/file/download/abc',
        fileName: 'report.pdf',
        localFilePath: localFile.path,
      );
      expect(client.getBytesCalls, 0);
      expect(cache.openedPaths, {localFile.path});
      expect(service.stateFor('msg-1').isReady, isTrue);

      // Saving as with registerLocalFile reads bytes from local disk with zero HTTP download calls.
      await service.registerLocalFile(
        id: 'msg-2',
        localPath: localFile.path,
        totalBytes: 4,
      );
      await service.saveAs(
        id: 'msg-2',
        source: '/api/chat/file/download/abc',
        fileName: 'report.pdf',
        localFilePath: localFile.path,
      );
      expect(client.getBytesCalls, 0);
      expect(picker.lastSaveRequest?.bytes, Uint8List.fromList([10, 20, 30, 40]));
    },
  );

  test('MessageRepository.sendLocalFile preserves localFilePath on sent message', () async {
    final tempDir = await Directory.systemTemp.createTemp('gotoim_repo_upload_');
    addTearDown(() => tempDir.delete(recursive: true));
    final localFile = File('${tempDir.path}/doc.txt');
    await localFile.writeAsString('hello attachment');

    final db = UnifiedDatabase(DatabaseConnection(NativeDatabase.memory()));
    await db.initialize();
    addTearDown(db.close);

    final repo = MessageRepository(
      api: _FakeUploadMessageApi(),
      dao: MessageDao(db),
    );
    final selected = await SelectedFile.fromXFile(XFile(localFile.path));
    final localMsg = await repo.createLocalFile(
      ownerId: 1,
      sessionUnitId: 'unit-1',
      file: selected,
    );
    final sentMsg = await repo.sendLocalFile(local: localMsg, file: selected);

    expect(sentMsg.state, 'sent');
    expect(sentMsg.serverId, 98765);
    expect(sentMsg.localFilePath, localFile.path);
  });

  test('OpenIdConnectAuthRepository.createDio uses 60s timeouts', () {
    dotenv.loadFromString(envString: 'AUTH_BASE_URL=https://auth.example.test');
    final env = AppEnvironment.fromDotEnv(AppFlavor.development);
    const deviceContext = ClientDeviceContext(
      appId: 'app',
      appName: 'App',
      appVersion: '1.0.0',
      deviceId: 'dev',
      deviceType: 'test',
      platform: 'test',
      brand: '',
      model: '',
      browser: '',
      pushClientId: '',
    );
    final dio = OpenIdConnectAuthRepository.createDio(env, deviceContext);
    expect(dio.options.connectTimeout, const Duration(seconds: 60));
    expect(dio.options.sendTimeout, const Duration(seconds: 60));
    expect(dio.options.receiveTimeout, const Duration(seconds: 60));
  });

  testWidgets('TwoLineAppBarTitle renders single-line and two-line titles', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          appBar: PreferredSize(
            preferredSize: Size.fromHeight(56),
            child: Column(
              children: [
                TwoLineAppBarTitle(title: '群公告', subtitle: '研发一组'),
                TwoLineAppBarTitle(title: '聊天设置'),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('群公告'), findsOneWidget);
    expect(find.text('研发一组'), findsOneWidget);
    expect(find.text('聊天设置'), findsOneWidget);
  });
}
