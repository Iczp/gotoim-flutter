/// URL 安全等级
enum UrlSecurityLevel {
  /// 官方/白名单安全域名，可静默直接访问
  safe,

  /// 未知/普通第三方外链，需展示风险警示（防诈骗/保护财产与隐私）
  warning,

  /// 违规/恶意/欺诈黑名单域名，强力阻断访问
  blocked,
}

/// URL 风险分类
enum UrlRiskCategory {
  /// 无风险 / 白名单
  none,

  /// 官方或受信任域名
  officialOrWhitelisted,

  /// 未经核实的第三方外链（灰名单）
  unknownThirdParty,

  /// 涉嫌电信诈骗 / 刷单返利 / 杀猪盘
  fraud,

  /// 钓鱼网站 / 冒充官方
  phishing,

  /// 色情低俗
  porn,

  /// 非法赌博
  illegalGambling,

  /// 病毒木马 / 恶意软件下载
  malware,

  /// 其他违规
  other,
}

/// URL 安全评估检测结果
class UrlSecurityCheckResult {
  const UrlSecurityCheckResult({
    required this.url,
    required this.domain,
    required this.level,
    required this.category,
    required this.message,
    this.interceptReason,
    this.checkedAt,
    this.source = 'local_engine',
    this.extra,
  });

  /// 待检查的完整 URL
  final String url;

  /// 提取的主机名/域名
  final String domain;

  /// 安全级别
  final UrlSecurityLevel level;

  /// 风险类别
  final UrlRiskCategory category;

  /// 展示给用户的提示说明
  final String message;

  /// 拦截的具体规则或原因
  final String? interceptReason;

  /// 检测时间戳
  final DateTime? checkedAt;

  /// 数据来源：'local_engine' (本地引擎) | 'backend_api' (后端风控服务) | 'cache'
  final String source;

  /// 扩展元数据
  final Map<String, dynamic>? extra;

  bool get isSafe => level == UrlSecurityLevel.safe;
  bool get isWarning => level == UrlSecurityLevel.warning;
  bool get isBlocked => level == UrlSecurityLevel.blocked;

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'domain': domain,
      'level': level.name,
      'category': category.name,
      'message': message,
      'interceptReason': interceptReason,
      'checkedAt': checkedAt?.toIso8601String(),
      'source': source,
      'extra': extra,
    };
  }
}
