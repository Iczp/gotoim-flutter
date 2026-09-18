class AppVersionDto {
  const AppVersionDto({
    required this.version,
    required this.versionCode,
    required this.title,
    required this.isForce,
    this.id,
    this.content,
    this.pkgUrl,
    this.pageUrl,
    this.appId,
    this.platform,
    this.isWidget = false,
    this.isPublic = true,
    this.isEnabled = true,
    this.issueDate,
    this.creationTime,
  });

  factory AppVersionDto.fromJson(Map<String, dynamic> json) {
    int parseVersionCode(Object? value) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    bool parseBool(Object? value) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      final str = value?.toString().toLowerCase();
      return str == 'true' || str == '1';
    }

    DateTime? parseDate(Object? value) {
      if (value == null) return null;
      return DateTime.tryParse(value.toString())?.toLocal();
    }

    return AppVersionDto(
      id: (json['id'] ?? json['Id'])?.toString(),
      version: (json['version'] ?? json['Version'] ?? '').toString(),
      versionCode: parseVersionCode(json['versionCode'] ?? json['VersionCode']),
      title: (json['title'] ?? json['Title'] ?? '发现新版本').toString(),
      content: (json['content'] ?? json['Content'])?.toString(),
      isForce: parseBool(json['isForce'] ?? json['IsForce']),
      isWidget: parseBool(json['isWidget'] ?? json['IsWidget']),
      isPublic: parseBool(json['isPublic'] ?? json['IsPublic']),
      isEnabled: parseBool(json['isEnabled'] ?? json['IsEnabled']),
      pkgUrl: (json['pkgUrl'] ?? json['PkgUrl'])?.toString(),
      pageUrl: (json['pageUrl'] ?? json['PageUrl'])?.toString(),
      appId: (json['appId'] ?? json['AppId'])?.toString(),
      platform: (json['platform'] ?? json['Platform'])?.toString(),
      issueDate: parseDate(json['issueDate'] ?? json['IssueDate']),
      creationTime: parseDate(json['creationTime'] ?? json['CreationTime']),
    );
  }

  final String? id;
  final String version;
  final int versionCode;
  final String title;
  final String? content;
  final bool isForce;
  final bool isWidget;
  final bool isPublic;
  final bool isEnabled;
  final String? pkgUrl;
  final String? pageUrl;
  final String? appId;
  final String? platform;
  final DateTime? issueDate;
  final DateTime? creationTime;

  Map<String, dynamic> toJson() => {
    'id': id,
    'version': version,
    'versionCode': versionCode,
    'title': title,
    'content': content,
    'isForce': isForce,
    'isWidget': isWidget,
    'isPublic': isPublic,
    'isEnabled': isEnabled,
    'pkgUrl': pkgUrl,
    'pageUrl': pageUrl,
    'appId': appId,
    'platform': platform,
    'issueDate': issueDate?.toIso8601String(),
    'creationTime': creationTime?.toIso8601String(),
  };
}
