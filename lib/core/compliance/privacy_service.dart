import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages user agreement & privacy policy compliance status and contents.
class PrivacyService extends ChangeNotifier {
  PrivacyService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _privacyAgreedKey = 'gotoim.privacy.agreed.v1';
  static const String _privacyAgreedAtKey = 'gotoim.privacy.agreed_at.v1';

  final FlutterSecureStorage _storage;
  bool _hasAgreed = false;
  DateTime? _agreedAt;
  bool _initialized = false;

  bool get hasAgreed => _hasAgreed;
  DateTime? get agreedAt => _agreedAt;
  bool get isInitialized => _initialized;

  Future<bool> initialize() async {
    if (_initialized) return _hasAgreed;
    try {
      final agreedStr = await _storage.read(key: _privacyAgreedKey);
      _hasAgreed = agreedStr == 'true';
      final agreedAtStr = await _storage.read(key: _privacyAgreedAtKey);
      if (agreedAtStr != null && agreedAtStr.isNotEmpty) {
        _agreedAt = DateTime.tryParse(agreedAtStr);
      }
    } catch (error) {
      debugPrint('[PrivacyService] read storage failed: $error');
      _hasAgreed = false;
    } finally {
      _initialized = true;
      notifyListeners();
    }
    return _hasAgreed;
  }

  Future<void> saveAgreement() async {
    final now = DateTime.now();
    _hasAgreed = true;
    _agreedAt = now;
    notifyListeners();
    try {
      await Future.wait(<Future<void>>[
        _storage.write(key: _privacyAgreedKey, value: 'true'),
        _storage.write(key: _privacyAgreedAtKey, value: now.toIso8601String()),
      ]);
    } catch (error) {
      debugPrint('[PrivacyService] save storage failed: $error');
    }
  }

  Future<void> resetAgreement() async {
    _hasAgreed = false;
    _agreedAt = null;
    notifyListeners();
    try {
      await Future.wait(<Future<void>>[
        _storage.delete(key: _privacyAgreedKey),
        _storage.delete(key: _privacyAgreedAtKey),
      ]);
    } catch (error) {
      debugPrint('[PrivacyService] reset storage failed: $error');
    }
  }

  static const String userAgreementTitle = '用户服务协议';
  static const String privacyPolicyTitle = '隐私保护政策';

  /// 线上网络版用户服务协议 URL
  static const String userAgreementUrl =
      'https://im.gotoim.com/legal/user-agreement.html';

  /// 线上网络版隐私保护政策 URL
  static const String privacyPolicyUrl =
      'https://im.gotoim.com/legal/privacy-policy.html';

  static const String userAgreementContent = '''
欢迎使用 GotoIM 客户端（以下简称“本软件”）。本协议是您与 GotoIM 平台运营方之间关于您使用本软件及相关服务所订立的法律协议。请您务必审慎阅读、充分理解各条款内容。

一、服务内容与账号规范
1.1 本软件为用户提供即时通讯、群组协作、音视频及多媒体文件传输等沟通协同服务。
1.2 您在注册、登录和使用本软件时，应提供真实、合法、有效的个人身份及联系信息，并对您账号下的一切行为独立承担全部法律责任。
1.3 用户不得利用本账号从事侵犯他人知识产权、名誉权、肖像权、隐私权及商业秘密等违法违规行为。

二、用户行为准则
2.1 用户在使用本软件时，必须遵守中华人民共和国相关法律法规，不得利用本服务制作、复制、发布、传播包含危害国家安全、煽动分裂国家、淫秽色情、暴力恐怖、虚假诈骗等违法有害信息。
2.2 未经运营方明确书面许可，任何用户不得对本软件进行反向工程、反编译、反汇编、注入代码或开发针对本软件的未经授权第三方插件。

三、知识产权声明
3.1 本软件所包含的系统架构、界面设计、图标、文字、代码、数据源以及相关专利均归本软件运营团队及权利人所有，受《中华人民共和国著作权法》及国际版权条约保护。

四、免责与争议解决
4.1 因不可抗力、网络通信运营商故障、设备兼容性问题等非平台可控因素造成的服务中断或数据延迟，平台将在第一时间内全力抢修，但依法免除相应连带责任。
4.2 本协议之订立、生效、解释与履行均适用中华人民共和国法律。如双方就本协议内容产生争议，应首先友好协商解决；协商不成的，均应提交本平台运营方住所地有管辖权的人民法院诉讼解决。
''';

  static const String privacyPolicyContent = '''
GotoIM 客户端深知个人信息对您的重要性，我们将按照法律法规的规定，遵循合法、正当、必要和诚信原则收集、使用、存储及保护您的个人信息。

一、我们如何收集和使用您的个人信息
1.1 账号注册与登录：当您注册或登录账号时，我们需要收集您的手机号码、用户名或账号信息，用于为您建立个人资料及验证登录凭据。
1.2 即时通讯功能：为了支持文本、表情、语音、图片、视频与文件传输，在获得您的明示授权后，本软件将根据具体使用场景请求相机、相册（读取与写入存储）、麦克风权限。
1.3 设备信息与网络状态：为了保障即时通讯长连接的连通性、离线消息推送及多端登录管理，在您同意本政策后，我们会收集您的设备型号、操作系统版本、唯一设备标识符（用于多端设备列表展示）、网络类型及 IP 地址。

二、敏感系统权限调用说明
2.1 相机权限：仅在您主动使用扫一扫（扫码登录/添加好友）或在聊天中拍照发送时调用。
2.2 相册/存储权限：仅在您主动选择发送图片、视频、下载保存聊天文件至本地时调用。
2.3 麦克风权限：仅在您主动发送语音消息、录音或进行音视频通话时调用。
2.4 传感器权限：距离传感器用于语音播放时听筒/扬声器智能切换防误触。

三、第三方 SDK 共享与合规承诺
3.1 未经您的明示授权与同意，我们绝不会主动向任何无关第三方共享、出售或出租您的个人信息。
3.2 在您未点击“同意”本政策前，我们绝不会提前初始化任何收集设备标识或个人信息的第三方 SDK。

四、您的个人信息权利
4.1 您有权查询、更正您的个人资料，或在“设置 - 账号管理”中申请注销您的账号。在注销账号后，我们将依法停止为您提供服务并删除或匿名化您的所有聊天数据。

五、联系与反馈
如果您对本隐私政策或个人信息保护有任何疑问、意见或建议，可通过应用内“设置 - 关于我们”或客服通道与我们联系。
''';
}

final privacyServiceProvider = ChangeNotifierProvider<PrivacyService>((ref) {
  final service = PrivacyService();
  service.initialize();
  return service;
});
