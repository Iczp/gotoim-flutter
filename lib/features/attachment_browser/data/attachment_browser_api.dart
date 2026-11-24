import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/application_providers.dart';
import '../../../core/network/api_client.dart';
import '../domain/attachment_browser_models.dart';

final attachmentBrowserApiProvider = Provider<AttachmentBrowserApi>((ref) {
  return AttachmentBrowserApi(ref.watch(apiClientProvider));
});

class AttachmentLibraryPageResult {
  const AttachmentLibraryPageResult({
    required this.totalCount,
    required this.items,
  });

  final int totalCount;
  final List<AttachmentAsset> items;
}

class AttachmentBrowserApi {
  AttachmentBrowserApi(this._client);
  final ApiClient _client;

  Future<AttachmentLibraryPageResult> queryLibrary({
    required AttachmentSource source,
    String? ownerId,
    String? sessionUnitId,
    String? sessionId,
    String? senderId,
    List<AttachmentMediaType>? mediaTypes,
    DateTime? startTime,
    DateTime? endTime,
    int? minSizeBytes,
    int? maxSizeBytes,
    List<String>? extensions,
    String? keyword,
    AttachmentSortBy sortBy = AttachmentSortBy.timeDesc,
    int skipCount = 0,
    int maxResultCount = 40,
  }) async {
    final msgTypes = mediaTypes != null && mediaTypes.isNotEmpty
        ? mediaTypes.map((e) => e.serverMessageType).toList(growable: false)
        : null;

    final query = <String, Object?>{
      if (ownerId != null && ownerId.isNotEmpty) 'OwnerId': ownerId,
      if (source == AttachmentSource.session || source == AttachmentSource.favorites)
        if (sessionUnitId != null && sessionUnitId.isNotEmpty)
          'SessionUnitId': sessionUnitId,
      if (source == AttachmentSource.session || source == AttachmentSource.favorites)
        if (sessionId != null && sessionId.isNotEmpty) 'SessionId': sessionId,
      if (senderId != null && senderId.isNotEmpty) 'SenderId': senderId,
      if (msgTypes != null) 'MessageTypes': msgTypes,
      if (startTime != null) 'StartTime': startTime.toUtc().toIso8601String(),
      if (endTime != null) 'EndTime': endTime.toUtc().toIso8601String(),
      if (minSizeBytes != null) 'MinSize': minSizeBytes,
      if (maxSizeBytes != null) 'MaxSize': maxSizeBytes,
      if (extensions != null && extensions.isNotEmpty) 'Extensions': extensions,
      if (keyword != null && keyword.trim().isNotEmpty)
        'Keyword': keyword.trim(),
      'Sorting': sortBy.serverSorting,
      'SkipCount': skipCount,
      'MaxResultCount': maxResultCount,
    };

    try {
      if (source == AttachmentSource.favorites) {
        final json = await _client.get<Map<String, dynamic>>(
          '/api/chat/favorite',
          query: query,
        );
        final rawItems = json['items'];
        final items = <AttachmentAsset>[];
        if (rawItems is List) {
          for (final row in rawItems) {
            if (row is! Map) continue;
            final map = Map<String, dynamic>.from(row);
            final msg = map['message'] is Map
                ? Map<String, dynamic>.from(map['message'] as Map)
                : map;
            items.add(
              AttachmentAsset.fromMessageJson(
                msg,
                source: AttachmentSource.favorites,
                overrideCreationTime: map['creationTime']?.toString(),
                overrideSessionUnitId: map['sessionUnitId']?.toString(),
              ),
            );
          }
        }
        return AttachmentLibraryPageResult(
          totalCount: (json['totalCount'] as num?)?.toInt() ?? items.length,
          items: items,
        );
      }

      final json = await _client.get<Map<String, dynamic>>(
        '/api/chat/message/attachment-list',
        query: query,
      );
      final rawItems = json['items'];
      final items = <AttachmentAsset>[];
      if (rawItems is List) {
        for (final row in rawItems) {
          if (row is! Map) continue;
          items.add(
            AttachmentAsset.fromMessageJson(
              Map<String, dynamic>.from(row),
              source: source == AttachmentSource.global
                  ? AttachmentSource.global
                  : AttachmentSource.session,
            ),
          );
        }
      }
      return AttachmentLibraryPageResult(
        totalCount: (json['totalCount'] as num?)?.toInt() ?? items.length,
        items: items,
      );
    } catch (_) {
      return const AttachmentLibraryPageResult(totalCount: 0, items: []);
    }
  }

  Future<AttachmentAsset?> uploadLocalFile({
    required String sessionUnitId,
    required File file,
  }) async {
    final name = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : 'file';
    final lower = name.toLowerCase();
    final isImage = lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp');
    final isVideo = lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi');

    final path = isImage
        ? '/api/chat/attachments/upload-image/$sessionUnitId'
        : '/api/chat/attachments/upload-file/$sessionUnitId';
    final formData = FormData.fromMap(<String, Object?>{
      'file': await MultipartFile.fromFile(file.path, filename: name),
    });
    final json = await _client.post<Map<String, dynamic>>(
      path,
      data: formData,
    );
    final url = (json['url'] ?? json['originalUrl'])?.toString() ?? '';
    if (url.isEmpty) return null;

    final sizeBytes = await file.length();
    final ext = name.contains('.') ? '.${name.split('.').last.toLowerCase()}' : null;

    return AttachmentAsset(
      id: json['blobId']?.toString() ??
          'local_${DateTime.now().millisecondsSinceEpoch}',
      source: AttachmentSource.local,
      mediaType: isImage
          ? AttachmentMediaType.image
          : isVideo
              ? AttachmentMediaType.video
              : AttachmentMediaType.file,
      fileName: name,
      url: url,
      thumbnailUrl: json['thumbnailUrl']?.toString(),
      blobId: json['blobId']?.toString(),
      extension: ext,
      sizeBytes: sizeBytes,
      sessionUnitId: sessionUnitId,
      creationTime: DateTime.now().toIso8601String(),
    );
  }
}
