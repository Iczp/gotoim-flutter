import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/qr_code_models.dart';
import 'qr_code_api.dart';

final qrCodeRepositoryProvider = Provider<QrCodeRepository>((ref) {
  return QrCodeRepository(ref.watch(qrCodeApiProvider));
});

class QrCodeRepository {
  QrCodeRepository(this._api);

  final QrCodeApi _api;

  /// 判断文本是否可能为 GotoIM 系统二维码（含 gotoim://、gotoim-dev:// 及 /q/{code} 短链）
  static bool isPotentialSystemQr(String rawText) {
    final text = rawText.trim();
    if (text.isEmpty) return false;
    final lower = text.toLowerCase();
    if (lower.startsWith('gotoim://') || lower.startsWith('gotoim-dev://')) {
      return true;
    }
    final uri = Uri.tryParse(text);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segs.length >= 2 &&
          (segs[0].toLowerCase() == 'q' || segs[0].toLowerCase() == 'qr')) {
        return true;
      }
      if (segs.length >= 3 &&
          segs[0].toLowerCase() == 'invite' &&
          segs[1].toLowerCase() == 'group') {
        return true;
      }
    }
    return false;
  }

  Future<QrCodeDetailModel> generate({
    int? ownerId,
    int? scene,
    int? inviterId,
    bool? isPermanent,
    int? expireDays,
    bool forceReset = false,
    String? title,
    int? maxUseCount,
    String? payloadJson,
  }) {
    return _api.generate(
      ownerId: ownerId,
      scene: scene,
      inviterId: inviterId,
      isPermanent: isPermanent,
      expireDays: expireDays,
      forceReset: forceReset,
      title: title,
      maxUseCount: maxUseCount,
      payloadJson: payloadJson,
    );
  }

  Future<QrCodeDetailModel> reset({
    int? ownerId,
    int? scene,
    int? inviterId,
    bool? isPermanent,
    int? expireDays,
    String? title,
    int? maxUseCount,
    String? payloadJson,
  }) {
    return _api.reset(
      ownerId: ownerId,
      scene: scene,
      inviterId: inviterId,
      isPermanent: isPermanent,
      expireDays: expireDays,
      title: title,
      maxUseCount: maxUseCount,
      payloadJson: payloadJson,
    );
  }

  Future<QrCodeScanDataModel> getByCode(
    String code, {
    int? currentChatObjectId,
  }) {
    return _api.getByCode(code, currentChatObjectId: currentChatObjectId);
  }

  Future<QrCodeScanDataModel?> resolve(
    String content, {
    int? currentChatObjectId,
  }) async {
    try {
      return await _api.resolve(
        content,
        currentChatObjectId: currentChatObjectId,
      );
    } catch (_) {
      return null;
    }
  }

  Future<QrCodeApplyOutputModel> apply({
    required String code,
    int? applicantChatObjectId,
    String? requestMessage,
  }) {
    return _api.apply(
      code: code,
      applicantChatObjectId: applicantChatObjectId,
      requestMessage: requestMessage,
    );
  }

  Future<void> disable(String id) => _api.disable(id);

  Future<ScanCodeResultModel?> scanCode({
    required String type,
    required String content,
    int? currentChatObjectId,
  }) async {
    try {
      return await _api.scanCode(
        type: type,
        content: content,
        currentChatObjectId: currentChatObjectId,
      );
    } catch (_) {
      return null;
    }
  }
}
