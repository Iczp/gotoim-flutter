import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/application_providers.dart';
import '../config/app_environment.dart';
import '../network/api_client.dart';
import 'url_security_level.dart';

/// URL 安全仓储接口（提供风控评估与违规上报，预留后端契约）
abstract class UrlSecurityRepository {
  /// 评估给定 URL 的安全风险等级
  Future<UrlSecurityCheckResult> checkUrl(String url);

  /// 提交 URL 或违规消息的投诉举报
  Future<bool> report({
    required String target,
    required String reason,
    String? description,
    String? messageId,
    String targetType = 'url',
  });

  /// 添加自定义受信任域名（白名单）
  void addTrustedHost(String host);

  /// 移除自定义受信任域名
  void removeTrustedHost(String host);

  /// 添加自定义阻断域名（黑名单）
  void addBlockedHost(String host, {String? reason});

  /// 移除自定义阻断域名
  void removeBlockedHost(String host);

  /// 获取当前所有生效的白名单域名
  Set<String> get trustedHosts;

  /// 获取当前所有生效的黑名单域名
  Map<String, String> get blockedHosts;

  /// 清空检测缓存
  void clearCache();
}

/// 默认 URL 安全风控仓储实现
///
/// 特性：
/// 1. 本地高性能多级安全检测（官方白名单、已知黑名单规则）；
/// 2. 内存 LRU/Map 缓存机制，避免高频链接重复校验；
/// 3. 预留向 ABP 后端 `/api/chat/security/check-url` 及 `/api/chat/security/report` 发起校验；
/// 4. 后端接口未就绪或离线时，本地风控引擎自动兜底降级。
class DefaultUrlSecurityRepository implements UrlSecurityRepository {
  DefaultUrlSecurityRepository({
    required AppEnvironment environment,
    ApiClient? apiClient,
  })  : _environment = environment,
        _apiClient = apiClient {
    _initDefaultRules();
  }

  final AppEnvironment _environment;
  final ApiClient? _apiClient;

  /// 内存校验缓存 key: normalizedUrl
  final Map<String, UrlSecurityCheckResult> _cache = {};

  /// 动态白名单集合（全小写 host）
  final Set<String> _dynamicTrustedHosts = {};

  /// 动态黑名单集合 host -> reason
  final Map<String, String> _dynamicBlockedHosts = {};

  /// 静态内置已知安全白名单（即使未配置在 env 也认可的基础域名）
  static const Set<String> _kBuiltInTrustedHosts = {
    'localhost',
    '127.0.0.1',
    '::1',
    'gotoim.com',
    'gotoim.dev',
    'github.com',
    'gitee.com',
  };

  /// 静态内置违规/钓鱼/欺诈特征域名（用于测试和本地风控拦截底线）
  static const Map<String, String> _kBuiltInBlockedHosts = {
    'malware-test.com': '已知恶意软件传播站点',
    'phishing-test.com': '已知仿冒钓鱼盗号站点',
    'scam-test.xyz': '涉嫌虚假投资与电信诈骗',
    'gambling-test.com': '非法赌博与高风险交易',
    'porn-test.com': '含有违法违规低俗内容',
  };

  void _initDefaultRules() {
    // 自动将配置在 Env 里的官方服务域名纳入受信任白名单
    _extractHost(_environment.apiBaseUrl)?.let(_dynamicTrustedHosts.add);
    _extractHost(_environment.authBaseUrl)?.let(_dynamicTrustedHosts.add);
    _extractHost(_environment.signalRBaseUrl)?.let(_dynamicTrustedHosts.add);
    _extractHost(_environment.statisticBaseUrl)?.let(_dynamicTrustedHosts.add);

    for (final host in _environment.deepLinkAllowedHosts) {
      if (host.trim().isNotEmpty) {
        _dynamicTrustedHosts.add(host.trim().toLowerCase());
      }
    }
  }

  String? _extractHost(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return null;
    try {
      final uri = Uri.parse(rawUrl.trim());
      if (uri.host.isNotEmpty) return uri.host.toLowerCase();
    } catch (_) {}
    return null;
  }

  @override
  Set<String> get trustedHosts => {
        ..._kBuiltInTrustedHosts,
        ..._dynamicTrustedHosts,
      };

  @override
  Map<String, String> get blockedHosts => {
        ..._kBuiltInBlockedHosts,
        ..._dynamicBlockedHosts,
      };

  @override
  void addTrustedHost(String host) {
    final clean = host.trim().toLowerCase();
    if (clean.isNotEmpty) {
      _dynamicTrustedHosts.add(clean);
      _cache.removeWhere((_, v) => v.domain == clean);
    }
  }

  @override
  void removeTrustedHost(String host) {
    final clean = host.trim().toLowerCase();
    _dynamicTrustedHosts.remove(clean);
    _cache.removeWhere((_, v) => v.domain == clean);
  }

  @override
  void addBlockedHost(String host, {String? reason}) {
    final clean = host.trim().toLowerCase();
    if (clean.isNotEmpty) {
      _dynamicBlockedHosts[clean] = reason ?? '用户或管理员标记为危险站点';
      _cache.removeWhere((_, v) => v.domain == clean);
    }
  }

  @override
  void removeBlockedHost(String host) {
    final clean = host.trim().toLowerCase();
    _dynamicBlockedHosts.remove(clean);
    _cache.removeWhere((_, v) => v.domain == clean);
  }

  @override
  void clearCache() {
    _cache.clear();
  }

  @override
  Future<UrlSecurityCheckResult> checkUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return const UrlSecurityCheckResult(
        url: '',
        domain: '',
        level: UrlSecurityLevel.blocked,
        category: UrlRiskCategory.malware,
        message: '链接地址为空',
        interceptReason: 'URL 格式无效',
      );
    }

    // 检查缓存
    if (_cache.containsKey(trimmed)) {
      final cached = _cache[trimmed]!;
      final isLocal =
          cached.source == 'local_whitelist' || cached.source == 'local_blacklist';
      // 本地静态规则长期有效；远端评估结果 60 秒内防高频重复请求，超过 60 秒自动回源，确保服务端加白瞬时生效
      final isFresh = isLocal ||
          (cached.checkedAt != null &&
              DateTime.now().difference(cached.checkedAt!) <
                  const Duration(seconds: 60));
      if (isFresh) {
        return UrlSecurityCheckResult(
          url: cached.url,
          domain: cached.domain,
          level: cached.level,
          category: cached.category,
          message: cached.message,
          interceptReason: cached.interceptReason,
          checkedAt: cached.checkedAt,
          source: 'cache',
          extra: cached.extra,
        );
      } else {
        _cache.remove(trimmed);
      }
    }

    Uri? uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (_) {
      return UrlSecurityCheckResult(
        url: trimmed,
        domain: '',
        level: UrlSecurityLevel.blocked,
        category: UrlRiskCategory.malware,
        message: '无法解析的非法网址',
        interceptReason: 'URL 语法不合法',
        checkedAt: DateTime.now(),
      );
    }

    // 校验 Scheme
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return UrlSecurityCheckResult(
        url: trimmed,
        domain: uri.host,
        level: UrlSecurityLevel.blocked,
        category: UrlRiskCategory.malware,
        message: '不支持该类型的外部链接协议 ($scheme)',
        interceptReason: '仅允许标准 HTTP/HTTPS 协议',
        checkedAt: DateTime.now(),
      );
    }

    final domain = uri.host.toLowerCase();
    if (domain.isEmpty) {
      return UrlSecurityCheckResult(
        url: trimmed,
        domain: '',
        level: UrlSecurityLevel.blocked,
        category: UrlRiskCategory.malware,
        message: '网址缺失主机域名',
        interceptReason: '缺少有效域名',
        checkedAt: DateTime.now(),
      );
    }

    // 1. 本地黑名单检查（命中直接强阻断）
    final allBlocked = blockedHosts;
    for (final entry in allBlocked.entries) {
      if (_matchesDomain(domain, entry.key)) {
        final result = UrlSecurityCheckResult(
          url: trimmed,
          domain: domain,
          level: UrlSecurityLevel.blocked,
          category: UrlRiskCategory.fraud,
          message: '据用户投诉及安全检测，该网页包含违法/违规/欺诈内容，已停止访问。',
          interceptReason: entry.value,
          checkedAt: DateTime.now(),
          source: 'local_blacklist',
        );
        _cache[trimmed] = result;
        return result;
      }
    }

    // 2. 本地官方及受信任白名单检查（命中直接判定安全）
    final allTrusted = trustedHosts;
    for (final trusted in allTrusted) {
      if (_matchesDomain(domain, trusted)) {
        final result = UrlSecurityCheckResult(
          url: trimmed,
          domain: domain,
          level: UrlSecurityLevel.safe,
          category: UrlRiskCategory.officialOrWhitelisted,
          message: '官方/受信域名',
          checkedAt: DateTime.now(),
          source: 'local_whitelist',
        );
        _cache[trimmed] = result;
        return result;
      }
    }

    // 3. 预留后端风控校验（若配置了 ApiClient 则尝试异步向服务端发起安全评级请求）
    if (_apiClient != null) {
      try {
        final res = await _apiClient
            .post<Map<String, dynamic>>(
              '/api/chat/security/check-url',
              data: {'url': trimmed, 'domain': domain},
            )
            .timeout(const Duration(milliseconds: 1200));
        final rawLevel = res['level'];
        final levelStr = rawLevel?.toString().toLowerCase();
        final level = (levelStr == 'safe' || levelStr == '0')
            ? UrlSecurityLevel.safe
            : ((levelStr == 'blocked' || levelStr == '2')
                ? UrlSecurityLevel.blocked
                : UrlSecurityLevel.warning);
        final result = UrlSecurityCheckResult(
          url: trimmed,
          domain: domain,
          level: level,
          category: _parseCategory(res['category']?.toString()),
          message: res['message']?.toString() ??
              (level == UrlSecurityLevel.blocked
                  ? '该网页已被平台安全中心拦截。'
                  : '您即将离开本应用访问第三方外链，请注意财产与信息安全。'),
          interceptReason: res['interceptReason']?.toString(),
          checkedAt: DateTime.now(),
          source: 'backend_api',
          extra: res,
        );
        _cache[trimmed] = result;
        return result;
      } catch (e) {
        // 后端接口未就绪或网络超时，平滑降级为本地预警策略
        debugPrint('[UrlSecurityRepository] 后端风控接口未连接或异常 ($e)，降级使用本地风控引擎');
      }
    }

    // 4. 未知第三方外链默认处理：预警（Warning），提示用户防范网络诈骗并告知离开应用
    final fallbackResult = UrlSecurityCheckResult(
      url: trimmed,
      domain: domain,
      level: UrlSecurityLevel.warning,
      category: UrlRiskCategory.unknownThirdParty,
      message: '您即将离开本应用访问第三方网站，请注意防范电信网络诈骗，保护个人信息与财产安全。',
      interceptReason: '非平台官方域名，未经验证的第三方链接',
      checkedAt: DateTime.now(),
      source: 'local_engine',
    );
    _cache[trimmed] = fallbackResult;
    return fallbackResult;
  }

  @override
  Future<bool> report({
    required String target,
    required String reason,
    String? description,
    String? messageId,
    String targetType = 'url',
  }) async {
    debugPrint(
      '[UrlSecurityRepository] 收到违规举报 -> target: $target, type: $targetType, reason: $reason, desc: $description',
    );

    // 如果举报的是 URL 且原因为严重违规，可在本地暂时标记为阻断
    if (targetType == 'url') {
      try {
        final uri = Uri.parse(target);
        if (uri.host.isNotEmpty) {
          // 暂不强行加全局阻断，避免恶意乱举报，但在本地记录处置日志
          debugPrint('[UrlSecurityRepository] 已登记涉嫌违规域名: ${uri.host}');
        }
      } catch (_) {}
    }

    // 预留向后端上报
    if (_apiClient != null) {
      try {
        await _apiClient.post<dynamic>(
          '/api/chat/security/report',
          data: {
            'target': target,
            'targetType': targetType,
            'reason': reason,
            'description': description ?? '',
            'messageId': messageId,
            'clientTime': DateTime.now().toIso8601String(),
          },
        );
        debugPrint('[UrlSecurityRepository] 举报成功同步至后端');
        return true;
      } catch (e) {
        debugPrint('[UrlSecurityRepository] 举报同步后端失败 ($e)，已在本地记录');
      }
    }

    return true;
  }

  bool _matchesDomain(String host, String pattern) {
    if (host == pattern) return true;
    if (pattern.startsWith('*.')) {
      final suffix = pattern.substring(2);
      return host.endsWith('.$suffix') || host == suffix;
    }
    // 默认支持子域名匹配（例如 *.gotoim.com 匹配 api.gotoim.com）
    return host.endsWith('.$pattern');
  }

  UrlRiskCategory _parseCategory(dynamic raw) {
    if (raw == null) return UrlRiskCategory.unknownThirdParty;
    if (raw is int && raw >= 0 && raw < UrlRiskCategory.values.length) {
      return UrlRiskCategory.values[raw];
    }
    final rawStr = raw.toString().toLowerCase();
    final intVal = int.tryParse(rawStr);
    if (intVal != null && intVal >= 0 && intVal < UrlRiskCategory.values.length) {
      return UrlRiskCategory.values[intVal];
    }
    return UrlRiskCategory.values.firstWhere(
      (e) => e.name.toLowerCase() == rawStr,
      orElse: () => UrlRiskCategory.unknownThirdParty,
    );
  }
}

extension _LetExt<T> on T {
  R let<R>(R Function(T it) block) => block(this);
}

/// Provider for UrlSecurityRepository
final urlSecurityRepositoryProvider = Provider<UrlSecurityRepository>((ref) {
  final env = ref.watch(appEnvironmentProvider);
  final apiClient = ref.watch(apiClientProvider);
  return DefaultUrlSecurityRepository(
    environment: env,
    apiClient: apiClient,
  );
});
